---
outline: 2
---

# 消息模型

> **读完本页你能**：看懂步级流里的四类消息与四种内容块、`StopReason` 的四个变体、错误如何走流的 `Err` 通道，以及为什么 `match` 必须带 `_` 臂。

SDK 的消息模型是一个 `Message` union。**形状现在就建齐**（四类消息 × 四种内容块），但 v1 **只填 llmy 的 `StepResult` 能给的**，其余字段类型就位而不填充，待 llmy 上游填充。

**状态说明**：brainary-agent-sdk 当前**全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；下方给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非占位草案。（⚪ = 暂缓 / 不纳入，非交付接口。）

## 一条流长什么样

```rust
use brainary_agent_sdk::{query, Message, ContentBlock, ModelSelection, Options};
use futures::StreamExt;

let options = Options::builder().model(ModelSelection::from_env()?).build()?;
let mut stream = query("介绍一下你自己。", options).await?;

while let Some(item) = stream.next().await {
    match item? {                                  // 单步失败在这里作为 Err 上抛
        Message::System(s) => println!("[system] {}", s.subtype),   // 开头一条 init
        Message::Assistant(a) => {
            for block in &a.content {
                if let ContentBlock::Text(t) = block { println!("{}", t.text); }
            }
        }
        Message::Result(r) => println!("停机：{:?}，共 {} 步", r.stop_reason, r.num_turns),
        _ => {}                                     // #[non_exhaustive] → 必须带 _ 臂
    }
}
```

预期序列：先一条 `System(subtype="init")`，然后若干 `Assistant`，最后一条 `Result` 收尾。

## 四类消息

`Message` 枚举（`#[non_exhaustive]`）：

| 变体 | 类型 | v1 行为 |
| --- | --- | --- |
| `Message::Assistant` | `AssistantMessage` | 模型走一步；v1 只填 `Text` 块 |
| `Message::User` | `UserMessage` | 用户轮；类型就位，v1 一般不填充 |
| `Message::System` | `SystemMessage` | v1 每次运行开头发一条 `subtype = "init"` |
| `Message::Result` | `ResultMessage` | 一次运行的终局摘要 |

字段（核对 `message.rs`）：

- `AssistantMessage { content: Vec<ContentBlock>, requested_tools: bool, model: Option<String>, error: Option<AssistantMessageError> }`
- `UserMessage { content: Vec<ContentBlock> }`（🟠 未来加 `parent_tool_use_id: Option<String>` / `tool_use_result: Option<...>`，见[下文](#usermessage-未来字段)）
- `SystemMessage { subtype: String, data: serde_json::Value }`（`init` 的 `data` 携带 `{ "model": ... }`）
- `ResultMessage { num_turns: usize, approx_context_tokens: Option<usize>, stop_reason: StopReason, usage: Option<Usage>, total_cost_usd: Option<f64>, is_error: bool, .. }`（追加字段见[下文](#resultmessage-追加字段)）

### AssistantMessage.error：结构化的单步失败类别 {#assistant-message-error}

`AssistantMessage.error: Option<AssistantMessageError>`（🟠 类型就位待上游）给「这一步为什么失败」一个**可 `match` 的类别**，让你不必去 `Err` 的错误字符串里做子串匹配。它是一个 `#[non_exhaustive]` 枚举：

```rust
#[non_exhaustive]
pub enum AssistantMessageError {
    AuthenticationFailed,   // 鉴权失败（API key 无效/过期）
    BillingError,           // 账单问题（额度/欠费）
    RateLimit,              // 触发限流，配合 RateLimitEvent 做退避
    InvalidRequest,         // 请求本身非法
    ServerError,            // 上游 5xx
    MaxOutputTokens,        // 单条回复触顶输出上限
    Unknown,                // 其余归为未知的情况
}
```

**它与 `Err(BrainaryError)` 流通道正交、互补而非替代**：

- `Err(BrainaryError)` 是**抛出的错误**——它终止流，你 `?` 上抛，决定「要不要继续」。
- `AssistantMessage.error` 是**这一步的失败分类标签**——它随 `Ok(Message::Assistant(_))` 一起到手（步没被抛掉的场景），让你在**不解析字符串**的前提下按 `AuthenticationFailed` / `RateLimit` / … 分支决策（例：`RateLimit` → 退避重试；`AuthenticationFailed` → 提示用户重新登录）。

```rust
Message::Assistant(a) => {
    if let Some(err) = &a.error {
        match err {
            AssistantMessageError::RateLimit => back_off().await,
            AssistantMessageError::AuthenticationFailed => prompt_relogin(),
            _ => {}                      // #[non_exhaustive] → 必须带 _ 臂
        }
    }
    for block in &a.content { /* … */ }
}
```

`error` 为 `None` 表示这一步没有可归类的失败。它不改变「抛出的错误走 `Err`」这条主线——两者可同时存在，也可各自单独出现。

## 内容块 ContentBlock {#content-block}

一条 `AssistantMessage` / `UserMessage` 的 `content` 是一个 `Vec<ContentBlock>`——**块是消息的组成单位**，归在消息类型之下（故不单开一页）。`ContentBlock` 枚举带 `#[serde(tag = "type", rename_all = "snake_case")]`，可序列化（transcript 靠它 round-trip）：

| 变体 | 字段 | v1 |
| --- | --- | --- |
| `Text` | `TextBlock { text: String }` | 🟠 |
| `ToolUse` | `ToolUseBlock { id: Option<String>, name: Option<String>, input: Value }` | 🟠 不填充 |
| `ToolResult` | `ToolResultBlock { tool_use_id, content: Option<String>, is_error: bool }` | 🟠 不填充 |
| `Thinking` | `ThinkingBlock { thinking: String, signature: Option<String> }` | 🟠 不填充（llmy `StepResult` 无 thinking 流） |

## 字段填充度

| 字段 | 规划状态 | 上游补齐后 |
| --- | --- | --- |
| `AssistantMessage.content = [Text]` | 🟠 规划填充文本 | — |
| `AssistantMessage.requested_tools` | 🟠 粗信号（llmy `did_tool_call()`） | 由 `ToolUse` 块取代 |
| `AssistantMessage.model` | 🟠 配置的模型名 | — |
| `ContentBlock::ToolUse / ToolResult / Thinking` | 🟠 类型就位，不填充 | 规划：填充 |
| `ResultMessage.num_turns / approx_context_tokens / stop_reason` | 🟠 规划填充 | — |
| `ResultMessage.usage / total_cost_usd` | 🟠 恒 `None` | 规划：真实值 |
| `AssistantMessage.error` | 🟠 类型就位，不填充 | 规划：填结构化失败类别 |
| `ResultMessage.is_error` | 🟠 规划恒 `false`（判失败改用 [`error`](#assistant-message-error)） | — |
| `ResultMessage.session_id / permission_denials` | 🟠 依赖会话面/权限面，恒 `None` | 规划：真实值 |
| `ResultMessage.duration_ms / api_error_status / errors` | 🟠 类型就位待上游 | 规划：真实值 |

## 成本：`total_cost_usd` 与 `usage` {#cost}

`ResultMessage` 的两个成本字段，**类型已就位、值待上游**：

| 字段 | 类型 | v1 | 上游后 |
| --- | --- | --- | --- |
| `ResultMessage.total_cost_usd` | `Option<f64>` | 🟠 恒 `None` | 🟠 真实花费（美元） |
| `ResultMessage.usage` | `Option<Usage>` | 🟠 恒 `None` | 🟠 真实 token 计量 |

`Usage` 是 token 计量，字段类型就位、值待 llmy 上游：

```rust
#[non_exhaustive]
pub struct Usage {
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub cache_creation_input_tokens: Option<u64>,
    pub cache_read_input_tokens: Option<u64>,
}
```

规划上，`r.total_cost_usd` 在落地初期恒为 `None`——**不是 bug，是数据待 llmy 上游透出**。调用方代码可照 `if let Some(cost) = r.total_cost_usd { … }` 写，上游补齐后无需改动即可拿到真实值（`#[non_exhaustive]` 保证加法式填充不破坏调用方）。

> 成本的**配置侧**是 `Options.billing_cap`（预算上限，规划中），见 [Options](/sdk/options#builder-方法逐项)。配置项进 `Options`、结果字段进 `ResultMessage`。

## ResultMessage 追加字段（登记规划） {#resultmessage-追加字段}

为完善结果消息的诊断面，`ResultMessage` 追加以下字段。它们随形状建齐、按依赖分状态填充（`#[non_exhaustive]` 保证加法式填充不破坏调用方）：

| 字段 | 类型 | 状态 | 说明 |
| --- | --- | --- | --- |
| `session_id` | `Option<String>` | 🟠 依赖会话面 | 会话面的 join key：把本次运行的 `Result` 关联回一个会话/transcript。会话面落地前恒 `None`。 |
| `duration_ms` | `Option<u64>` | 🟠 类型就位待上游 | 本次运行的墙钟耗时（毫秒）。 |
| `api_error_status` | `Option<u16>` | 🟠 配合 error 分类 | 终止性 API 错误的 HTTP 状态码；与 [`AssistantMessageError`](#assistant-message-error) 配套，让你既知类别又知状态码。无终止错误时 `None`。 |
| `permission_denials` | `Option<Vec<PermissionDenial>>` | 🟠 依赖权限面 | 本次运行被权限面拒绝的工具调用记录。权限面落地前恒 `None`。 |
| `errors` | `Option<Vec<String>>` | 🟠 类型就位待上游 | 循环级错误字符串（如 max-turns 提示），用于诊断而非分支。 |

`is_error` 的语义不变——v1 **恒 `false`**；要判断「这一步/这次为何失败」，请用结构化的 [`AssistantMessageError`](#assistant-message-error)（步级类别）与 `api_error_status`（HTTP 状态码），而非 `is_error` 布尔。

## RateLimitEvent / RateLimitInfo：限流状态流事件 {#rate-limit-event}

::: tip 状态：🟠 已规划（原为「不建模」）
限流状态原先仅登记为不建模；现改为架构已规划：作为一类**流事件**透出，让调用方能实现退避。类型形态先给出，v1 不透出。
:::

`RateLimitEvent` 在限流状态变化时进入消息流（如从 `Allowed` 变为 `AllowedWarning`），携带一份 `RateLimitInfo`：

```rust
#[non_exhaustive]
pub struct RateLimitEvent {
    pub rate_limit_info: RateLimitInfo,
    pub session_id: String,
}

#[non_exhaustive]
pub struct RateLimitInfo {
    pub status: RateLimitStatus,
    pub resets_at: Option<i64>,         // 窗口重置的 Unix 时间戳
    pub rate_limit_type: Option<RateLimitType>,
    pub utilization: Option<f64>,       // 已消耗比例 0.0..=1.0
    // …其余 overage 字段
}

#[non_exhaustive]
pub enum RateLimitStatus {
    Allowed,          // 正常
    AllowedWarning,   // 逼近上限
    Rejected,         // 已被限流
}

/// 限流维度（如按 token / 按请求）；opaque，随上游细化。
#[non_exhaustive]
pub enum RateLimitType {
    Tokens,
    Requests,
    Other,
}
```

- `AllowedWarning`：逼近上限——在撞到硬限前提前警示用户。
- `Rejected`：已被限流——用 `resets_at` 决定退避多久后重试（配合 [`AssistantMessageError::RateLimit`](#assistant-message-error)）。

因为 `Message` 是 `#[non_exhaustive]`，未来新增的 `RateLimit` 变体会落进你已有的 `_` 臂，不破坏现有 `match`。

## UserMessage 未来字段 {#usermessage-未来字段}

`UserMessage` 当前只有 `content`。待 subagent（子代理）与工具结果回填落地后，追加两个字段（🟠 类型就位、v1 不填充）：

| 字段 | 类型 | 用途 |
| --- | --- | --- |
| `parent_tool_use_id` | `Option<String>` | 该用户轮由哪个工具调用触发（子代理嵌套时的父指针）。 |
| `tool_use_result` | `Option<...>` | 承载工具执行结果，喂回下一步。 |

v1 不填充这两个字段；形状先建齐，subagent/工具结果面落地后按加法式填充。

## StopReason 四变体

`Result` 里的 `stop_reason` 说明为什么停：

| 变体 | 含义 |
| --- | --- |
| `Stopped` | 模型不再请求工具，正常完成 |
| `MaxTurns` | `max_turns` 护栏触顶 |
| `Interrupted` | `InterruptHandle` 请求了步间中断 |
| `ContextExhausted` | 上下文溢出护栏在下一步前触发 |

**注意：没有 `Error` 变体**——错误不是一种停机原因，它走流的 `Err` 通道（见下）。护栏细节见 [中断与护栏](/sdk/interrupt-and-guardrails)。

## 错误模型：流的 Err 与终局 Result 正交

流的每一项是 `Result<Message>`。这两条通道互不干扰：

- **单步失败** → `Err(BrainaryError)`，流随即结束。你可以直接 `?` 上抛。
- **正常终局** → `Ok(Message::Result(_))`，`stop_reason` 说明原因。

所以你**永远不会**在 `ResultMessage` 里读到「出错了」这种布尔——`is_error` 在 v1 恒为 `false`。要按**原因**分支，用步级的 [`AssistantMessageError`](#assistant-message-error)（结构化类别）与 `ResultMessage.api_error_status`（HTTP 状态码），而非 `is_error`。抛出的错误类型 `BrainaryError` 与 core/SDK 共用，见 类型与错误。

## #[non_exhaustive] → match 需 `_` 臂

`Message`、`ContentBlock`、`StopReason`、各消息结构体都标了 `#[non_exhaustive]`，这样 M5 补字段/变体时不破坏你的代码。代价是：跨 crate `match` 它们时**必须带 `_` 臂**（如上例），否则编译不过。

## 相关

- [两个入口：消费消息流](/sdk/query-and-client)
- [错误处理](/sdk/errors) —— 错误走 `Err` 通道的完整接法
- [中断与护栏](/sdk/interrupt-and-guardrails) · [会话导出](/sdk/transcript)
- [SDK 总览](/sdk/overview) · [能力边界](/sdk/limits)
