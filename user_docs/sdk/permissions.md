---
outline: 2
---

# 权限模型

> **读完本页你能**：分清「装了哪些工具（可用性）」与「这次准不准调（授权）」是两回事；掌握 agent 授权控制面的 6 个真实权限模式、`allowed_tools` / `disallowed_tools` 声明式规则、`CanUseTool` 逐次回调与 `ToolPermissionContext`、`PermissionResult` 裁决、以及 `PermissionUpdate` 运行期改规则的机制在 Brainary 里的规划形态与承诺签名。

**状态图例（全站统一 4 态）**：🟢 已实现 · 🟡 类型/旋钮就位待上游 · 🟠 架构已规划未实现 · ⚪ 暂缓/仅登记

本页整面是 **🟠 架构已规划未实现**：授权控制面尚未落地，但下面给出的类型、字段、builder 方法都是**已承诺的形态**，供上游架构对齐，不是占位草案。

## 为什么需要权限面

权限是 agent 的**控制面（control plane），不是一个布尔开关**。当模型请求调用一个工具——尤其是有副作用的（写文件、发网络请求、跑 shell 命令）——总得有人回答「**这一次**准不准调？」。这个「谁来答、按什么答、答完能不能改」的整套机制，就是权限面。

关键是要把两件常被混为一谈的事分开——Brainary **刻意**把它们分开：

- **可用性（availability）＝ 装了哪些工具**：agent 只能看到你在装配期挂进 `Options` 的工具/primitive。没装的能力，模型根本感知不到。这是**静态**的粗粒度边界。
- **授权（authorization）＝ 这次准不准调**：即便一个工具装上了、对模型可见，具体某一次调用仍要过授权判定——可能自动放行、可能拒绝、可能弹回给你的回调裁决。这是**动态、逐次**的细粒度控制。

一个工具「可用」不等于「每次调用都被批准」。本页讲的模式、规则、回调、裁决，全部属于第二件事——授权。第一件事（装配期约束）见本页末尾 [与装配期手段的关系](#与装配期手段的关系)。

## PermissionMode —— 6 个真实模式

权限模式是授权面的**全局档位**，决定「默认情况下工具调用怎么裁决」。这不是三选一的玩具枚举，而是 6 个各自承载不同自主度的真实模式。Rust 侧是枚举，Python 侧是字符串字面量，一一对应。

```rust
// 🟠 架构已规划未实现。以下为承诺形态。
#[non_exhaustive]
pub enum PermissionMode {
    /// 标准权限行为：未被规则预批的有副作用调用走 can_use_tool 回调裁决。
    Default,
    /// 自动接受文件编辑（写/改文件不再逐次问），其余照常。快速迭代的常用默认。
    AcceptEdits,
    /// 规划模式：只探索、不改动。模型可读、可分析，但落地改动前须经
    /// exit_plan_mode 显式退出规划、拿到批准。
    Plan,
    /// 未被预先批准的一律直接拒绝，而非弹回询问。适合无人值守、只跑白名单。
    DontAsk,
    /// 跳过权限检查（显式 ask 规则仍会拦下）。危险，仅在完全可信环境使用。
    BypassPermissions,
    /// 由模型分类器逐次判定放行/拒绝——把「危不危险」的判断交给模型自身。
    Auto,
}
```

| 模式 | 语义 | 映射的 Brainary 自主度档 |
| --- | --- | --- |
| `Default` | 有副作用调用走回调裁决 | 有人值守 · 逐次把关 |
| `AcceptEdits` | 自动接受文件编辑，其余照常 | 半自主 · 编辑放手（迭代默认） |
| `Plan` | 只探索不改动，改动前须 `exit_plan_mode` | 只读侦察 · 计划先行 |
| `DontAsk` | 未预批一律拒绝，不询问 | 无人值守 · 白名单封闭 |
| `BypassPermissions` | 跳过检查（ask 规则仍拦） | 全放手 · 仅可信环境 |
| `Auto` | 模型分类器逐次判定 | 模型自裁 · 委托判断 |

其中 `Plan` 与 `AcceptEdits` 是一等公民，值得单独强调：

- **`Plan`（规划模式）**：让 agent 先「只看不动」——读代码、跑分析、列方案，但**不落地任何改动**。要真正动手，模型必须调用 `exit_plan_mode` 显式退出规划模式并拿到你的批准。这是「先给我看计划再执行」这种工作流的原生支持。
- **`AcceptEdits`（自动接受编辑）**：文件编辑不再逐次弹窗，直接放行——这是**快速迭代场景的推荐默认**。其它有副作用的调用（如 shell、网络）仍照常走裁决，兼顾速度与安全。

## allowed_tools / disallowed_tools —— 声明式规则

除了逐次回调，还有一层**声明式**的静态规则，直接挂在 `Options` 上，无需写代码即可表达「这些自动批、这些一律拒」。

```rust
// 🟠 架构已规划未实现。承诺的 builder 形态：
Options::builder()
    .allowed_tools(["Read", "Grep", "Bash(git status)"])   // 自动批准，不弹回调
    .disallowed_tools(["WebFetch", "Bash(rm *)"])          // 拒绝
    .permission_mode(PermissionMode::Default)
    .build()?;
```

规则的语义要点：

- **`disallowed_tools` 里的裸工具名**（如 `"WebFetch"`）：把该工具**从模型上下文里彻底移除**——模型看不到、也调不了。
- **作用域规则**（如 `"Bash(rm *)"`）：工具本身仍可用，但**任何模式下**（包括 `BypassPermissions`）匹配到的调用都被拒绝。这是给「命令级黑名单」用的。
- **`allowed_tools` 是自动批准，不是限定集**：列进去的工具/调用免过回调直接放行；但它**不会**把 agent 限制成「只能用这些」——没列到的工具照样可用，只是要落到 `permission_mode` 与 `can_use_tool` 去裁决。要真正禁用，用 `disallowed_tools`。

裁决优先级：先看声明式规则（allow/deny），命中即定；未命中再看 `permission_mode`；仍需询问时才落到 `can_use_tool` 回调。

## CanUseTool 逐次回调 + ToolPermissionContext

当声明式规则和模式都没能拍板、流程解析为「需要问一次」时，才会调用 `can_use_tool` 回调。它是**异步**的，能拿到工具名、入参，以及一个 `ToolPermissionContext`——上下文是**回调自己的入参**，是一等核心类型，不是内部管线。

```rust
// 🟠 架构已规划未实现。承诺形态。
use std::sync::Arc;
use std::future::Future;
use std::pin::Pin;

/// 逐次工具授权回调：仅在权限流解析为「需询问」时被调用。
/// 已被 allowed_tools / 规则 / acceptEdits|bypassPermissions 放行的调用不会触发它。
pub type CanUseTool = Arc<
    dyn Fn(
            /* tool_name */ &str,
            /* input */ &serde_json::Value,
            /* context */ &ToolPermissionContext,
        ) -> Pin<Box<dyn Future<Output = PermissionResult> + Send>>
        + Send
        + Sync,
>;

/// 传给权限回调的上下文——一等核心类型。
#[non_exhaustive]
pub struct ToolPermissionContext {
    /// CLI/运行时给出的权限更新建议（可原样塞回 Allow.updated_permissions 持久化）。
    pub suggestions: Vec<PermissionUpdate>,
    /// 触发本次请求的被拦路径（如 Bash 命令访问了允许目录之外的路径）。
    pub blocked_path: Option<String>,
    /// 本次询问被触发的原因（如 PreToolUse hook 返回 "ask" 时转发的理由）。
    pub decision_reason: Option<String>,
    /// 完整的询问提示句，如「agent 想读取 foo.txt」——有值时用作主提示文案。
    pub prompt: Option<String>,
    /// 预留：中断信号支持。
    pub signal: Option<()>,
}
```

挂进配置：`Options::builder().can_use_tool(cb)`。

`ToolPermissionContext` 让回调**基于上下文**决策，而非只看工具名：`suggestions` 给出可持久化的规则建议、`blocked_path` 指出踩到的沙箱边界、`decision_reason` 说明为什么走到询问、`prompt` 提供现成的人类可读提示文案。

> 要**无条件拦截每一次**工具调用（含被规则/模式放行的），用 [PreToolUse hook](/sdk/hooks) 而非 `can_use_tool`——后者只在流程解析为「需询问」时触发。

## PermissionResult —— 裁决

回调返回 `PermissionResult`，二选一：

```rust
// 🟠 架构已规划未实现。承诺形态。
#[non_exhaustive]
pub enum PermissionResult {
    Allow {
        /// 改写后的入参：放行的同时替换模型给的参数（如脱敏、纠正路径）。None = 原样放行。
        updated_input: Option<serde_json::Value>,
        /// 顺带持久化的权限更新（如「以后这类调用都自动批」）。
        updated_permissions: Option<Vec<PermissionUpdate>>,
    },
    Deny {
        /// 拒绝理由，回灌给模型让它换招。
        message: String,
        /// 是否顺带中断本次运行，而非仅拒绝这一次调用。
        interrupt: bool,
    },
}
```

- **`Allow.updated_input`**：放行时**改写入参**——你可以在批准的同时纠正/脱敏模型给的参数，模型会拿到改写后的版本执行。
- **`Allow.updated_permissions`**：放行时**落一条规则**——把本次决定沉淀成持久规则（配合 `ToolPermissionContext.suggestions` 常见做法：把建议原样塞回），下次同类调用免问。
- **`Deny.message`**：拒绝理由回灌给模型，引导它换一种做法。
- **`Deny.interrupt`**：为 `true` 时不只拒这一次，而是**中断整个运行**——适合踩到硬红线要立即刹车的场景。

## PermissionUpdate / PermissionRuleValue —— 运行期改规则

上面 `updated_permissions` 里塞的、以及运行期 `set_permission_mode` 背后动的，都是同一套**规则变更机制**。它是**公开机制**，不是内部实现细节——凡是想在运行中动态改授权（切模式、加规则、放开目录）的地方都走它。

```rust
// 🟠 架构已规划未实现。承诺形态。
#[non_exhaustive]
pub struct PermissionUpdate {
    /// 操作类型。
    pub kind: PermissionUpdateKind,
    /// add/replace/remove 规则时的规则集。
    pub rules: Option<Vec<PermissionRuleValue>>,
    /// 规则操作的行为：允许 / 拒绝 / 询问。
    pub behavior: Option<PermissionBehavior>,       // Allow | Deny | Ask
    /// setMode 操作要切到的模式。
    pub mode: Option<PermissionMode>,
    /// addDirectories / removeDirectories 操作的目录集。
    pub directories: Option<Vec<String>>,
    /// 更新落到哪里（决定作用域与是否跨会话持久）。
    pub destination: Option<PermissionDestination>,
}

#[non_exhaustive]
pub enum PermissionUpdateKind {
    AddRules, ReplaceRules, RemoveRules,
    SetMode,
    AddDirectories, RemoveDirectories,
}

#[non_exhaustive]
pub enum PermissionDestination {
    UserSettings,     // 用户级
    ProjectSettings,  // 项目级
    LocalSettings,    // 项目本地（.local，跨会话持久）
    Session,          // 仅本会话
}

/// 一条待增/改/删的权限规则。
pub struct PermissionRuleValue {
    /// 目标工具名，如 "Bash"。
    pub tool_name: String,
    /// 作用域内容，如 "git status"、"rm *"；None 表示整工具粒度。
    pub rule_content: Option<String>,
}
```

一句话：`set_permission_mode` 是 `PermissionUpdate { kind: SetMode, mode: ... }` 的门面；回调里的 `updated_permissions` 是 `AddRules` 的门面；放开一个新目录是 `AddDirectories`。`destination` 决定这条更新是「只管这次会话」还是「写进本地设置跨会话生效」。

## 权限接口一览

| Brainary 规划 | 状态 |
| --- | --- |
| `PermissionMode` 枚举（6 变体） | 🟠 |
| `.allowed_tools([..])` / `.disallowed_tools([..])` builder | 🟠 |
| `CanUseTool` 回调类型 + `.can_use_tool(cb)` | 🟠 |
| `ToolPermissionContext` 一等核心类型 | 🟠 |
| `PermissionResult` 枚举（`Allow`/`Deny`） | 🟠 |
| `PermissionUpdate` / `PermissionRuleValue`（+ `Kind`/`Destination`/`Behavior`） | 🟠 |

## 与装配期手段的关系

授权面（本页）是**动态、逐次**的控制；它之上还有一层**静态、装配期**的粗粒度边界，二者互补：

- **装/不装即可用性边界**：agent 只能调用你在 `Options` 里显式挂载的工具/primitive——不装的能力模型碰不到。这是最粗、最硬的一道墙（见 [Options](/sdk/options)）。
- **文件夹沙箱**：把文件读写钉在给定目录内，越界访问会触发 `blocked_path`。
- **构建期校验**：工具重名、命名空间冲突在 `build()` 当场报错。

装配期决定「装了什么、能碰哪个目录」（可用性）；本页的模式/规则/回调/裁决决定「装上的东西这一次准不准用、用之前改不改」（授权）。

## 桥接

授权治理不止本页一条路，它和这些面协同：

- **[Hooks](/sdk/hooks)**：`PreToolUse` gate 能无条件拦下**每一次**工具调用（`can_use_tool` 只在「需询问」时触发）；`PermissionRequest` hook 也参与授权流。
- **[会话/客户端方法](/sdk/sessions)**：运行期用 `set_permission_mode` 动态切档，背后就是 `PermissionUpdate { kind: SetMode }`。
- **[内置工具目录](/sdk/builtin-tools)**：命令级沙箱与 bash 工具配套——`"Bash(rm *)"` 这类作用域拒绝规则针对的正是它。

## 相关

- [Hooks 子系统](/sdk/hooks) —— PreToolUse gate 与 PermissionRequest hook
- [内置工具目录](/sdk/builtin-tools) —— bash 工具与命令沙箱
- [自定义工具 FunctionTools](/sdk/tools) —— 工具怎么装进 agent（可用性）
- [Options 统一配置](/sdk/options) —— 装配期能力约束与沙箱
- [会话管理](/sdk/sessions) —— 运行期 `set_permission_mode` 切档
- [边界与路线图](/sdk/limits) —— 覆盖矩阵与里程碑
