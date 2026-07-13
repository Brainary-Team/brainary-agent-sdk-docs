---
outline: 2
---

# 两个入口：query() 与 BrainaryClient

> **读完本页你能**：分清一次性 `query()` 与有状态 `BrainaryClient` 的语义与流生命周期，明白中断为什么做成句柄，并会用 `BrainaryClient` 的透传方法读取系统提示、上下文估算、单步与会话导出。

SDK 只有两个入口，共用同一套 [Options](/sdk/options) 和同一条步级 [Message 流](/sdk/messages)。区别只有一句话：**agent 归谁持有、上下文是否跨调用累积。**

## 该用哪个？

| 你的场景 | 选 | 为什么 |
| --- | --- | --- |
| 问一次就完事，不需要接着追问 | `query()` | 每次调用**新建一个 agent**，跑完即弃；返回的流自己持有 agent（`'static`），可随意 move 到别的 task |
| 多轮对话，要接续上下文 / 工作记忆 | `BrainaryClient` | **长期持有同一个 agent**，逐轮追加消息，上下文自动累积（进程内原生 resume）|

一句话记忆：**`query()` = 一次性；`BrainaryClient` = 会话。** 两者用的 `Options` 和 `Message` 流完全一样，随时可从前者换到后者。

> 下面的代码片段都省略了外层的 `async fn { … }` 包装——它们都位于某个异步函数体内。

## query()：一次性

```rust
use brainary_agent_sdk::{query, Message, ModelSelection, Options};
use futures::StreamExt;

let options = Options::builder().model(ModelSelection::from_env()?).build()?;

// query() 每次新建一个 agent（相当于「开一个新会话」），跑完即弃
let mut stream = query("介绍一下你自己。", options).await?;
while let Some(item) = stream.next().await {
    match item? {
        Message::Assistant(a) => println!("{a:?}"),
        Message::Result(r)    => println!("停机：{:?}", r.stop_reason),
        _ => {}   // Message 是 #[non_exhaustive]，match 必须带 _ 臂
    }
}
```

- **一问一答**：`query(prompt, options)` 新建一个 agent，把 `prompt` 跑到停机，然后丢弃。想再问一句就得再调一次 `query()`，且**不记得**上一次的内容。
- **流可自由 move**：返回的流自己持有那个 agent，所以生命周期是 `'static`——你可以把它 move 进另一个 `tokio::spawn` 的 task 里慢慢消费。
- **签名**：`async fn query(prompt: impl Into<String>, options: Options) -> Result<MessageStream<'static>>`。
- **流式输入（🟠 已规划）**：除字符串外，还规划一个接**输入流**的入口，用于「输入本身是一条流」的场景。见[下文](#流式输入)。

## BrainaryClient：有状态多轮

```rust
use brainary_agent_sdk::{BrainaryClient, ModelSelection, Options};
use futures::StreamExt;

let options = Options::builder().model(ModelSelection::from_env()?).enable_memory(true).build()?;
let mut client = BrainaryClient::connect(options).await?;

// 第一轮
{
    let mut stream = client.query("查一下东京天气");
    // 本例不看每步内容，只把流跑完：`item?` 上抛单步错误，`let _ =` 丢弃成功的消息
    while let Some(item) = stream.next().await { let _ = item?; }
}   // ← 流在这里离开作用域，归还对 client 的 &mut 借用

// 第二轮：无需重传上文，client 自己记得（进程内原生 resume）
{
    let mut stream = client.query("那把它记到记忆里");
    while let Some(item) = stream.next().await { let _ = item?; }
}
```

- **一次 connect，长期持有**：`BrainaryClient::connect(options).await?` 建好 agent 并持有它，连同它名下活着的 primitive 资源（如 MCP 连接）——所以 `client` 必须一直留在作用域里，别提前 drop。
- **逐轮追问，自动记上下文**：每调一次 `client.query(prompt)` 就追加一轮对话并驱动它；上一轮的消息、工作记忆都还在。这就是进程内的原生 resume，不用你手动把历史拼回 prompt。
- **每轮的流要及时释放**：`client.query(...)` 返回的流借用了 `&mut client`，流没结束前你**碰不了 `client`**（连发起下一轮都不行）。所以上面用 `{ … }` 把每一轮的流圈在一个小作用域里，跑完即释放，然后才能开下一轮。

## 流式输入（str 之外）{#流式输入}

::: warning 架构已规划、尚未实现（🟠）
字符串 `prompt` 是 🟢；把**输入流**当 prompt 的形态已承诺、v1 未实现。
:::

除了「一次给一个字符串」，还规划一个接 **`impl Stream<Item = UserInput>`** 的输入入口——**边产出边喂**：输入流每 `yield` 一条用户消息，agent 就多收一段。这是流式输入（streaming-input）模式。适合语音逐句到达、上游 agent 边算边产出等「输入本身是流」的场景。输出端仍是同一条 `MessageStream`：

```rust
// 🟠 架构已规划未实现。承诺形态（函数名以最终实现为准）。
async fn query_streaming(
    prompt: impl Stream<Item = UserInput> + Send + 'static,
    options: Options,
) -> Result<MessageStream<'static>>;

// UserInput = 一条用户输入（文本或内容块），与字符串输入等价但可持续追加
pub struct UserInput {
    pub content: Vec<ContentBlock>,
}
```

Python 侧对应 `prompt: str | AsyncIterable[dict]`，见 [Python：流式输入](/sdk-py/query-and-client#流式输入)。

## 怎么中断一次运行

想在 agent 跑到一半时喊停，用 `InterruptHandle`，三步：

1. **开流之前**先取句柄：`let handle = client.interrupt_handle();`
2. 把 `handle`（可克隆）move 进定时器 / 信号处理 / 另一个 task；
3. 条件满足时调用 `handle.interrupt()`。

```rust
let mut client = BrainaryClient::connect(options).await?;
let handle = client.interrupt_handle();   // ← 必须在开流「之前」取

// handle 可 move 进定时器 / 信号处理 / 另一个 task
tokio::spawn(async move {
    // …某个条件满足时：
    handle.interrupt();                    // 请求步间中断
});

let mut stream = client.query("一个很长的任务");
while let Some(item) = stream.next().await { let _ = item?; }
```

`handle.interrupt()` 只是置一个标志位；驱动循环会在**下一步开始前**退出，并以 `StopReason::Interrupted` 收尾。llmy **没有「步内取消」**——正在进行中的那一步会先跑完，不会被硬打断。中断、`max_turns`、上下文溢出这三道护栏的细节见 [中断与护栏](/sdk/interrupt-and-guardrails)。

### 为什么中断做成句柄，而不是 `client.interrupt()` 方法？

因为 `client.query()` 返回的流**独占了 `&mut client`**：流还活着时你根本拿不到 `&client`，也就无法调用任何 `&self` 方法去发中断。于是把中断信号外置成一个可克隆的句柄 `InterruptHandle`（内部就是一个 `Arc<AtomicBool>`）——它跨轮有效，能自由 move 到别的 task，绕开了借用冲突。这也是为什么第 1 步强调「**开流之前**」取句柄。

## BrainaryClient 透传方法

除 `connect` / `query` 外，`BrainaryClient` 暴露以下方法（均为真实公有方法）：

| 方法 | 签名要点 | 作用 |
| --- | --- | --- |
| `interrupt_handle()` | `-> InterruptHandle` | 取可克隆中断句柄，跨轮有效；开流前取 |
| `system_prompt()` | `-> String` | 渲染后的系统提示 |
| `approx_context_tokens()` | `-> Option<usize>` | 当前上下文的近似 token 数 |
| `context_window()` | `-> u64` | 本模型的上下文窗口（max input tokens）；未注册模型为 `0`（窗口未知） |
| `step_once()` | `async -> Result<Message>` | 不开流地走一步（映射 llmy `step`），不推入用户消息，返回一条 `Message::Assistant` |
| `revert()` | `async -> Result<()>` | 回退最近一步（映射 llmy `revert_step`） |
| `conversation()` | `-> Vec<TranscriptMessage>` | 至今的会话，转成 SDK 自有的 transcript 消息 |
| `export_transcript()` | `-> SessionTranscript` | 整个会话的可序列化只读快照 |

下面按用途分三组，各给一个最小示例（`client` 为已 `connect` 的 `BrainaryClient`；②③ 作用在**已累积的会话**上，示例假设此前已跑过至少一轮 `query()`）。

**① 只读检视**——`system_prompt` / `approx_context_tokens` / `context_window` 都是「看一眼」的 getter，只读不改会话：

```rust
println!("{}", client.system_prompt());                    // 渲染后的完整系统提示（发给模型的那份）
println!("≈{:?} tokens", client.approx_context_tokens());  // 当前上下文约占多少 token；None = 估不出
println!("窗口 {}", client.context_window());              // 本模型最大输入 token；0 = 未注册、窗口未知
```

**② 导出会话**——`conversation()` 给你一个「至今为止的消息列表」（可数长度、可遍历），`export_transcript()` 给你一份可序列化、可落盘的只读快照：

```rust
let msgs = client.conversation();                 // Vec<TranscriptMessage>：每追问一轮就变长
println!("已累积 {} 条消息", msgs.len());

let transcript = client.export_transcript();      // 整段会话的只读快照，可 serde 序列化存档，见 /sdk/transcript
```

**③ 手动单步与回退**——`step_once()` + `revert()` 是流式 `query()` 之外的另一种驱动方式：**你自己一步步推**，而不是开一根流让它跑到停机。`step_once()` 不推入新的用户消息，只在**已有会话**上往前走一步，返回模型这一步的 `Message::Assistant`；`revert()` 把最近一步撤掉。两者配合可做「试一步，不满意就退回」：

```rust
// 前提：此前已 client.query(...) 过，会话里已有内容
let step = client.step_once().await?;   // 手动走一步（不加新用户消息），拿到这一步的 Assistant 消息
// …检查这一步的结果，若不满意就撤销：
client.revert().await?;                 // 回退最近一步，会话退回上一状态
```

> **何时用手动单步？** 绝大多数场景直接消费 `query()` 的流即可。只有当你要**逐步介入**——每走一步就审查/打分、决定是否回退重来——才需要 `step_once`/`revert`；注意它们只作用于已累积的会话，`step_once` 本身不会替你追加用户提问。

> `context_window()` 返回 `0` 意味着模型未在 llmy 注册表登记、窗口未知。此时上下文溢出护栏**不生效**，回退到 `max_turns`——原因见 [中断与护栏](/sdk/interrupt-and-guardrails)。会话导出的结构与限制见 [会话导出](/sdk/transcript)。

## 完整方法面 {#full-method-face}

下表逐一列出 `BrainaryClient` 的完整方法面及其落点与状态。**🟢=已实现 · 🟡=类型就位待上游 · 🟠=架构已规划、未实现**（状态图例见 [总览](/sdk/overview#v1-能力填充度)）：

| 方法 | 状态 | 说明 / 去处 |
| --- | --- | --- |
| `BrainaryClient::connect(options)` | 🟢 | 见上「有状态多轮」 |
| `client.query(prompt)` | 🟢 | 返回借用 `&mut self` 的步级流 |
| 直接消费 `query()` 返回的 `Message` 流 | 🟢 | Rust 里流即返回值，无需单独的 receive 方法，见 [消息模型](/sdk/messages) |
| `interrupt_handle()` + `InterruptHandle::interrupt()` | 🟢 | 因借用冲突外置成句柄，见上「怎么中断」 |
| `disconnect`：`Drop`（`client` 离开作用域自动释放） | 🟢 | Rust 用 RAII，无显式 disconnect |
| `get_server_info`：部分由 `system_prompt()` / `context_window()` getter 覆盖 | 🟡 | 无单一聚合方法；分散在只读 getter |
| `set_model(model)`：`Options.model` 装配时固定，运行时切换未实现 | 🟠 | 需重建 client；见 [边界](/sdk/limits) |
| `set_permission_mode(mode)` | 🟠 | 权限模型整体未落地，见 [权限模型](/sdk/permissions) |
| `rewind_files(msg_id)`（文件检查点）：语义不同，`revert()` 回退一步；文件级检查点未做 | 🟠 | 见下「Brainary 独有」与 [边界](/sdk/limits) |
| `get_mcp_status()` / `reconnect_mcp_server()` / `toggle_mcp_server()`（MCP 运行时控制） | 🟠 | v1 仅装配期挂载 MCP，见 [自定义工具](/sdk/tools) |
| `stop_task(task_id)`（后台任务）：无后台任务模型 | 🟠 | 见 [边界](/sdk/limits) 路线图 |
| `get_session_messages()` 等会话函数：进程内 `conversation()` 有；跨进程历史 session 未做 | 🟠 | 语义差异见 [会话管理](/sdk/sessions) |

**Brainary 独有（全部 🟢）**：`step_once()` / `revert()`（手动单步与回退）、`conversation()` / `export_transcript()`（会话快照）、`approx_context_tokens()` / `context_window()` / `system_prompt()`（只读检视）——即上一节详述的透传方法。

> 这些 🟠 项**不是遗漏**，而是有意识的裁剪：它们是架构上该有、但 v1 未实现的面，先登记接口便于后续与底层对齐。逐项决策与理由见 [边界与路线图](/sdk/limits#coverage-matrix) 的覆盖矩阵。

## 相关

- [Options 统一配置](/sdk/options)
- [消息模型](/sdk/messages) · [中断与护栏](/sdk/interrupt-and-guardrails) · [会话导出](/sdk/transcript)
- 进阶（架构已规划）：[会话管理](/sdk/sessions) 🟠 · [权限模型](/sdk/permissions) 🟠 · [错误处理](/sdk/errors)
- [SDK 总览](/sdk/overview) · [能力边界](/sdk/limits)
