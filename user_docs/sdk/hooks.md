---
outline: 2
---

# Hooks 生命周期钩子（架构已规划）

> **读完本页你能**：理解 hooks 是**包裹 agent 循环的确定性、代码驱动治理层**——在固定生命周期点触发，可观察 / 改写 / 拦截；掌握 Brainary 目标规格里的 `HookEvent` / `HookMatcher` / `HookCallback` / `HookContext` / `HookInput` / `HookJSONOutput` 六件套的建议性 Rust 签名；看懂 `PreToolUse` 的 `permissionDecision` 与逐次授权回调 `CanUseTool` 如何组成「权限桥」。

**状态说明**：brainary-agent-sdk 当前**全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；下方给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非占位草案。（⚪ = 暂缓 / 不纳入，非交付接口。）

::: warning 整个 Hooks 子系统为「架构已规划、尚未实现」（🟠）
下面的类型与签名是**目标规格**：定义「一个编码智能体 SDK 的钩子面 *应当* 长什么样」，用来牵引仍在演进的底层架构。它们**不是**当前实现的映射，当前 v1 的 `Options` 里没有 `hooks`。签名均为**已承诺的形状**（committed signatures），供与底层对齐时定稿——不是「签名待定」。北极星见 [SDK 总览](/sdk/overview)。
:::

## 为什么需要 hooks：确定性治理层

agent 循环里其实有两套「决策」在跑，务必分清：

- **LLM 自己发起的工具调用**：模型在推理中决定「我要调 `Bash` 跑这条命令」——这是**概率性**的，取决于提示词、上下文、模型当下的判断，你无法保证它每次都对。
- **hooks**：由**你的代码**在固定生命周期点（工具调用前后、用户提交提示、子 agent 起停、压缩前……）**确定性**地触发。它不参与模型推理，而是**包裹**着推理循环，在每个卡点上观察、改写、或直接拦截。

换句话说：LLM 的工具调用是 agent「想做什么」，hooks 是宿主「允许 / 记录 / 篡改它做什么」。这是一层**代码驱动的护栏**，行为可预测、可测试、可审计。

> **实践指引**：若要对**每一次**工具调用都设卡（gate every tool call），应当用 `PreToolUse` **hook**，而不是只依赖逐次权限回调 `CanUseTool`。权限回调面向「这一次调用允不允许」的裁决；`PreToolUse` hook 则是全量、无遗漏地拦在所有工具调用之前的确定性关口。两者可叠加，见下文[权限桥](#hooks-权限桥)。

## HookEvent：Brainary 目标事件集

`HookEvent` 枚举 agent 循环里可挂钩的生命周期点。Brainary 首版提供 **10 个核心事件**（另有若干事件仅登记）：

| 事件 | 触发时机 | 状态 |
| --- | --- | --- |
| `PreToolUse` | 工具执行**之前**——可改写入参 / 裁决放行拦截 | 🟠 |
| `PostToolUse` | 工具执行**成功之后**——可审计、可改写工具输出 | 🟠 |
| `PostToolUseFailure` | 工具执行**失败之后**——拿到 `error`、可回灌上下文 | 🟠 |
| `UserPromptSubmit` | 用户提交一条提示时——可注入 `additionalContext` | 🟠 |
| `Stop` | 主循环停止时 | 🟠 |
| `SubagentStop` | 子 agent 停止时 | 🟠 |
| `SubagentStart` | 子 agent 启动时 | 🟠 |
| `PreCompact` | 上下文**压缩之前**——随 core 压缩落地（M6） | 🟠 |
| `Notification` | 通知类事件（如需要用户关注） | 🟠 |
| `PermissionRequest` | 需要一次权限裁决时——可编程化处理，见[权限桥](#hooks-权限桥) | 🟠 |

> `PreCompact` 依赖 core 的**压缩**能力，随 M6 落地（自动压缩由 core 拥有，见 [边界与路线图](/sdk/limits)）。在压缩落地前，该事件永不触发。

**Brainary 暂不纳入（⚪ 仅登记）**：`SessionStart` / `SessionEnd` / `Setup`（以及 `TeammateIdle` / `TaskCompleted` / `ConfigChange` / `WorktreeCreate` / `WorktreeRemove` / `PostToolBatch` / `MessageDisplay`）——它们不在首版核心事件集内，暂不纳入，仅在此登记以免遗漏。

## HookMatcher / HookCallback / HookContext

### HookMatcher — 匹配器 + 逐匹配器超时

一个 `HookMatcher` 把「匹配哪些工具」和「跑哪些回调」绑在一起。`matcher` 是工具名或竖线分隔的模式（如 `"Bash"`、`"Write|Edit"`）；`matcher = None` 表示**匹配全部工具**。`timeout` 是该匹配器下所有回调的整体超时（默认 60 秒）。

```rust
// 🟠 架构已规划、尚未实现——以下为目标规格（committed signature）。

/// 把一组 hook 回调绑定到工具名/模式，并附带整体超时。
pub struct HookMatcher {
    /// 工具名或竖线分隔模式，如 "Bash"、"Write|Edit"；None = 匹配全部工具。
    pub matcher: Option<String>,
    /// 命中时按序执行的回调列表。
    pub hooks: Vec<HookCallback>,
    /// 本匹配器下所有回调的整体超时，默认 60s。
    pub timeout: Option<std::time::Duration>,
}
```

### HookCallback — 回调形态

回调是一个 async 闭包 / trait 对象，拿到强类型的 `HookInput`、可选的 `tool_use_id`、以及 `HookContext`，返回 `HookJSONOutput`。承诺形状：

```rust
use std::sync::Arc;
use std::future::Future;
use std::pin::Pin;

/// hook 回调：(input, tool_use_id, context) -> HookJSONOutput。
/// 形态为 Arc<dyn Fn(...) -> 未来> 的 async 闭包；等价的 async trait 见下。
pub type HookCallback = Arc<
    dyn Fn(
            HookInput,
            Option<String>,          // tool_use_id：工具相关事件才有
            HookContext,
        ) -> Pin<Box<dyn Future<Output = HookJSONOutput> + Send>>
        + Send
        + Sync,
>;

/// 等价的 trait 形态（二选一，最终以对齐结论为准）：
#[async_trait::async_trait]
pub trait Hook: Send + Sync {
    async fn call(
        &self,
        input: HookInput,
        tool_use_id: Option<String>,
        ctx: HookContext,
    ) -> HookJSONOutput;
}
```

### HookContext — 上下文

`HookContext` 携带回调运行时的旁路信息。首版只固定一个中止信号位（对齐后续步内取消能力）：

```rust
pub struct HookContext {
    /// 预留：中止信号支持（对齐 SDK 的 abort/interrupt）。
    pub signal: Option<AbortSignal>,
}
```

## HookInput：按事件名判别的联合体

`HookInput` 是一个**判别联合**（discriminated union），判别键为事件名。所有变体都带一组公共基字段：

```rust
/// 所有 hook 输入共有的基字段。
pub struct BaseHookInput {
    pub session_id: String,
    pub transcript_path: String,
    pub cwd: String,
    pub permission_mode: Option<String>,
}

/// 按事件名判别的 hook 输入联合体。
#[non_exhaustive]
pub enum HookInput {
    PreToolUse(PreToolUseHookInput),
    PostToolUse(PostToolUseHookInput),
    PostToolUseFailure(PostToolUseFailureHookInput),
    UserPromptSubmit(UserPromptSubmitHookInput),
    Stop(StopHookInput),
    SubagentStop(SubagentStopHookInput),
    SubagentStart(SubagentStartHookInput),
    PreCompact(PreCompactHookInput),
    Notification(NotificationHookInput),
    PermissionRequest(PermissionRequestHookInput),
}
```

至少这三个 tool/prompt 相关变体的载荷字段需固定：

```rust
/// PreToolUse：工具执行前。
pub struct PreToolUseHookInput {
    pub base: BaseHookInput,
    pub tool_name: String,
    pub tool_input: serde_json::Value,
    pub tool_use_id: String,
    pub agent_id: Option<String>,     // 在子 agent 内触发时有值
    pub agent_type: Option<String>,
}

/// PostToolUse：工具成功后，多出 tool_response。
pub struct PostToolUseHookInput {
    pub base: BaseHookInput,
    pub tool_name: String,
    pub tool_input: serde_json::Value,
    pub tool_response: serde_json::Value,   // 工具执行的返回
    pub tool_use_id: String,
    pub agent_id: Option<String>,
    pub agent_type: Option<String>,
}

/// UserPromptSubmit：用户提交提示时。
pub struct UserPromptSubmitHookInput {
    pub base: BaseHookInput,
    pub prompt: String,
}
```

> `PostToolUseFailure` 额外带 `error: String`、`is_interrupt: Option<bool>`；`PreCompact` 带 `trigger: "manual" | "auto"` 与 `custom_instructions: Option<String>`；`PermissionRequest` 带 `tool_name` / `tool_input` / `permission_suggestions`。逐变体全表见规格底稿。

## HookJSONOutput：裁决与执行面

这是 hooks 的**承重部分**——回调靠返回值来放行、拦截、注入消息、改写输入输出。返回值是控制字段 + 裁决字段 + 逐事件专属输出（`hookSpecificOutput`）的组合：

```rust
/// hook 回调的返回：控制 + 裁决 + 逐事件专属输出。
pub struct HookJSONOutput {
    // —— 控制字段 ——
    /// 是否继续（默认 true）。false 即中止后续处理。
    pub r#continue: Option<bool>,
    /// continue=false 时给出的停止原因。
    pub stop_reason: Option<String>,
    /// 从记录里隐藏本 hook 的 stdout。
    pub suppress_output: Option<bool>,

    // —— 裁决字段 ——
    /// "block"：拦截本次动作。
    pub decision: Option<Decision>,          // Decision::Block
    /// 展示给用户的告警消息。
    pub system_message: Option<String>,
    /// 回灌给模型的反馈理由。
    pub reason: Option<String>,

    // —— 逐事件专属输出 ——
    pub hook_specific_output: Option<HookSpecificOutput>,
}

pub enum Decision { Block }
```

**`HookSpecificOutput`** 是按事件名判别的专属输出。两个承重变体：`PreToolUse` 携带**权限裁决** `permissionDecision`，`UserPromptSubmit` 携带**上下文注入** `additionalContext`：

```rust
#[non_exhaustive]
pub enum HookSpecificOutput {
    /// PreToolUse：可裁决放行/拒绝/追问/延后，并可改写入参。
    PreToolUse {
        /// allow=直接放行；deny=拦截；ask=转人工追问；defer=交回默认权限流程。
        permission_decision: Option<PermissionDecision>,
        permission_decision_reason: Option<String>,
        /// 改写后的工具入参（放行但修改参数）。
        updated_input: Option<serde_json::Value>,
        additional_context: Option<String>,
    },
    /// PostToolUse：可改写工具输出、追加上下文。
    PostToolUse {
        additional_context: Option<String>,
        updated_tool_output: Option<serde_json::Value>,
    },
    /// UserPromptSubmit：向模型注入额外上下文。
    UserPromptSubmit { additional_context: Option<String> },
    /// PermissionRequest：直接给出权限决定。
    PermissionRequest { decision: serde_json::Value },
}

/// PreToolUse 的四态权限裁决。
#[non_exhaustive]
pub enum PermissionDecision { Allow, Deny, Ask, Defer }
```

> `permissionDecision` 的四态是权限桥的核心：`allow` 直接放行、`deny` 就地拦截、`ask` 升级为人工追问、`defer` 把决定权交回默认权限流程（即 `CanUseTool` 回调 / `PermissionMode`）。详见[下文](#hooks-权限桥)。

## 配置：hooks 怎么挂进 Options

hooks 通过 `Options` 挂载，键为 `HookEvent`、值为 `HookMatcher` 列表（同一事件可挂多个匹配器，按序执行）。页面级见 [Options 统一配置](/sdk/options)。

```rust
// 🟠 目标规格：Options 上的 .hooks(...) builder（当前 v1 尚无此旋钮）。
use std::collections::HashMap;

let options = Options::builder()
    .hooks(HashMap::from([
        (HookEvent::PreToolUse, vec![
            HookMatcher { matcher: Some("Bash".into()), hooks: vec![validate_bash], timeout: None },
            HookMatcher { matcher: None,                hooks: vec![audit_log.clone()], timeout: None },
        ]),
        (HookEvent::PostToolUse, vec![
            HookMatcher { matcher: None, hooks: vec![audit_log], timeout: None },
        ]),
    ]))
    .build()?;
```

## 范式示例

### (a) PreToolUse：拦截危险 bash 命令

命中 `Bash` 工具、命令里含 `rm -rf /` 时，返回 `permissionDecision: deny` 就地拦截：

```rust
use std::sync::Arc;

let validate_bash: HookCallback = Arc::new(|input, _tool_use_id, _ctx| {
    Box::pin(async move {
        if let HookInput::PreToolUse(p) = &input {
            if p.tool_name == "Bash" {
                let cmd = p.tool_input.get("command")
                    .and_then(|v| v.as_str()).unwrap_or("");
                if cmd.contains("rm -rf /") {
                    return HookJSONOutput {
                        hook_specific_output: Some(HookSpecificOutput::PreToolUse {
                            permission_decision: Some(PermissionDecision::Deny),
                            permission_decision_reason: Some("危险命令已拦截".into()),
                            updated_input: None,
                            additional_context: None,
                        }),
                        ..Default::default()
                    };
                }
            }
        }
        HookJSONOutput::default()   // 默认放行（不返回裁决即透传）
    })
});
```

### (b) PostToolUse：审计日志

对**所有**工具（`matcher = None`）在执行后记一条审计日志，不改变行为：

```rust
let audit_log: HookCallback = Arc::new(|input, _tool_use_id, _ctx| {
    Box::pin(async move {
        if let HookInput::PostToolUse(p) = &input {
            eprintln!("[audit] 工具已执行：{}", p.tool_name);
        }
        HookJSONOutput::default()
    })
});
```

## Hooks ↔ 权限桥 {#hooks-权限桥}

hooks 与[权限模型](/sdk/permissions)在「谁能调工具」上交汇，三条通路要分清：

- **`PreToolUse` 的 `permissionDecision`**：hook 在工具调用前直接给四态裁决。`allow` / `deny` 就地定案；`ask` 升级为人工追问；`defer`**把决定权交回默认权限流程**——也就是逐次授权回调 `CanUseTool` 与全局档位 `PermissionMode`（见 [权限模型](/sdk/permissions)）。这让「代码规则先过一遍、拿不准的再落到权限回调」成为自然的两级结构。
- **`CanUseTool` 回调**：面向「**这一次**调用允不允许」的逐次裁决，看得到工具名与入参、可返回 `Allow`/`Deny`（可带理由或改写入参）。与 `PreToolUse` hook 的区别是：hook 是**全量、无遗漏**的确定性关口（推荐用它 gate 每次调用），回调是**逐次、可交互**的授权点。二者叠加：hook 先筛，`defer` 的落到回调。
- **`PermissionRequest` hook**：当需要一次权限裁决时触发，让你**编程化**地处理权限决定（返回 `HookSpecificOutput::PermissionRequest { decision }`），而非只靠交互式追问。它也承接沙箱回退——当模型请求越出沙箱执行（`dangerouslyDisableSandbox`）时，请求会回退到权限系统，由你的授权逻辑裁决。

**`decision_reason` 的流动**：`PreToolUse` 的 `permission_decision_reason`（以及回调 `Deny` 的理由）会流入权限上下文并回灌给模型，让模型知道「为什么被拦」、据此调整下一步——拦截不是黑箱，而是带反馈的护栏。

## 相关

- [权限模型](/sdk/permissions) —— `PermissionMode` / `CanUseTool` / `PermissionResult` 三件套
- [内置工具目录](/sdk/builtin-tools) —— hook 的 `matcher` 匹配的工具名从何而来
- [自定义工具 FunctionTools](/sdk/tools) —— 工具怎么装进 agent
- [中断、护栏与上下文](/sdk/interrupt-and-guardrails) —— 另一层运行期护栏（步边界中断 / max_turns / 上下文溢出）
- [边界与路线图](/sdk/limits) —— 覆盖矩阵与里程碑（含 M6 压缩 / `PreCompact`）
