---
outline: 2
---

# 中断、护栏与上下文

> **读完本页你能**：在步边界协作式中断一个运行、用 `max_turns` 与上下文溢出护栏兜底、理解「0 窗口坑」为什么会让护栏回退到 `max_turns`，以及 `auto_compact` 在 v1 的占位含义。

## 概念简述

SDK 自己驱动 agent 的循环：每完成一个 `step()` 产出一条 `Message`。在**每一步之前**，驱动器按顺序检查三道护栏——中断、`max_turns`、上下文溢出——任一触发就以对应的 `StopReason` 收尾，发一条 `Message::Result` 后结束流。

所有 `StopReason`（来自 `crates/brainary-agent-sdk/src/message.rs`）：

| StopReason | 触发 |
| ---------- | ---- |
| `Stopped` | 模型不再请求工具调用（正常完成） |
| `MaxTurns` | `max_turns` 护栏触顶 |
| `Interrupted` | `InterruptHandle` 请求了步边界中断 |
| `ContextExhausted` | 步前上下文溢出护栏触发 |

> 错误**不是** stop reason。单步失败走流的 `Err(BrainaryError)` 通道，正常终局才是 `Ok(Message::Result(_))`，二者正交。

## 步间协作式中断

中断信号是一个可克隆的 `InterruptHandle`（内部 `Arc<AtomicBool>`），而不是 client 上的方法。方法签名：

```rust
impl InterruptHandle {
    pub fn interrupt(&self);         // 请求一次步边界中断
    pub fn is_interrupted(&self) -> bool;
}
```

请求后，驱动器在**下一步开始之前**退出，并以 `StopReason::Interrupted` 收尾。这是**协作式**、发生在步边界：llmy 没有步内取消，所以当前正在跑的那一步会先跑完，中断在下一步之前生效（步内中断归 M5，见 [v1 边界](/sdk/limits)）。

### 为什么中断是句柄，不是方法

`client.query(...)` 返回的流独占 `&mut self`，流存活期间取不到 `&self`——所以中断信号必须**外置**为可克隆句柄，而且要在**开流之前**取得，再 move 进定时器 / 信号处理 / 另一个 task。借用关系的完整解释见 [query 与 client](/sdk/query-and-client)。

```rust
use brainary_agent_sdk::{BrainaryClient, Message, Options};
use futures::StreamExt;

let mut client = BrainaryClient::connect(options).await?;
// 1) 开流「之前」取句柄——开流后 &mut 被独占,就再也拿不到了
let handle = client.interrupt_handle();

// 2) 句柄可 clone,move 进另一个 task；这里演示 5 秒后触发中断
let h = handle.clone();
tokio::spawn(async move {
    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    h.interrupt();
});

// 3) 开流并消费,直到收到收尾的 Result
let mut stream = client.query("做一个多步任务");
while let Some(item) = stream.next().await {
    match item? {   // item 是 Result<Message,_>：单步失败在此作为 Err 上抛
        Message::Result(r) => {
            println!("停止原因：{:?}，共 {} 步", r.stop_reason, r.num_turns);
            break;
        }
        _ => {}   // 本例只关心 Result；其余变体忽略（Message 亦 #[non_exhaustive]，须留 _ 臂）
    }
}
```

被中断时，末条 `Result` 的 `stop_reason` 是 `StopReason::Interrupted`。

## `max_turns` 循环护栏

用 `Options::builder().max_turns(n)` 设定。驱动器在每步前检查 `turns >= n`，触顶以 `StopReason::MaxTurns` 停。

- `max_turns(0)` 会在**任何网络请求之前**就停（第一步都不跑），只发 `System(init)` + `Result(MaxTurns, num_turns=0)`。这既是护栏语义，也是离线自测驱动器的手段。
- 不设 `max_turns` 则无轮数上限，靠 `Stopped` / 上下文护栏收尾。

## 上下文溢出护栏

每步之前，驱动器用近似上下文 token 数（llmy `approx_context_tokens`）比对模型的 `max_input_tokens`；一旦逼近就以 `StopReason::ContextExhausted` **明确停**，而不是让请求静默出错。判定逻辑（`crates/brainary-agent-sdk/src/client.rs::context_exhausted`）：

```rust
fn context_exhausted(approx_tokens: Option<usize>, max_input_tokens: u64) -> bool {
    if max_input_tokens == 0 {
        return false;                 // 窗口未知 → 不设护栏（见下）
    }
    match approx_tokens {
        Some(tokens) => tokens as u64 >= max_input_tokens,
        None => false,                // 用量未知 → 不猜
    }
}
```

你可以从 client 读到这两个量：

```rust
println!("≈{:?} tokens / 窗口 {}", client.approx_context_tokens(), client.context_window());
```

## ⚠️ 重点：0 窗口坑

**未在注册表里的模型**（经 llmy `custom_model`，即用 `name,in_price,out_price` 自定义定价那种）的 `max_input_tokens = 0`——表示**窗口未知**，而非「窗口为零」。

- 此时上下文护栏**故意不生效**（`return false`），运行回退到 `max_turns` 兜底。
- 原因：对一个未知的窗口设护栏，会把「`approx_tokens >= 0`」判为真而**在第 0 轮就误停**，agent 一步都跑不了。这正是首次真机运行修掉的回归。
- 实践建议：用自定义/未注册模型时，**务必设 `max_turns`**，因为上下文护栏对它是失效的。

## `auto_compact`：v1 仅 `Off` 占位

`Options.auto_compact` 是上下文治理的旋钮，但 v1 里**只有 `Off` 有意义**：

```rust
#[non_exhaustive]
pub enum AutoCompact {
    Off,        // v1 唯一可用；默认值
    // core-gated (M6): Auto, Threshold(_)
}
```

自动压缩策略由 **core 拥有**（M6），尚未落地。旋钮现在就摆好，是为了 M6 落地后「翻开即用」、加法式无破坏。SDK 是门面不是内核，凡触及上下文治理这类核心语义，决策权在 core——手动 `compact()` 也因此**故意不暴露**（footgun）。裁决理由见 [v1 边界与路线图](/sdk/limits)。

## 下一步

- [query 与 client](/sdk/query-and-client) —— 借用关系、为何中断句柄要开流前取
- [消息模型](/sdk/messages) —— `ResultMessage` 各字段与 `StopReason` 全貌
- [v1 边界与路线图](/sdk/limits) —— 步内中断（M5）、自动压缩（M6）排期
