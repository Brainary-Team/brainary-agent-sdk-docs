---
outline: 2
---

# 会话导出（Transcript）

> **读完本页你能**：从一个 `BrainaryClient` 导出可序列化的会话快照、把它写成 JSON、理解它如何从 llmy 上下文映射为 SDK 自有类型，以及为什么 v1 只能导出、不能续跑。

## 概念简述

`BrainaryClient` 是有状态多轮的（进程内 resume，上下文跨 `query` 调用累积）。任意时刻你都能拿到一份**只读的会话快照**用于审计或持久化——这就是 transcript。它是 **SDK 自有类型**，可 `Serialize` / `Deserialize`，**不外泄任何 llmy 类型**。

## 核心 API

来自 `crates/brainary-agent-sdk/src/transcript.rs` 与 `client.rs`：

```rust
// 整份会话快照
pub struct SessionTranscript {
    pub messages: Vec<TranscriptMessage>,
}

// 一条消息：角色 + SDK 自有的内容块
pub struct TranscriptMessage {
    pub role: String,
    pub content: Vec<ContentBlock>,
}

impl BrainaryClient {
    pub fn conversation(&self) -> Vec<TranscriptMessage>;   // 目前为止的对话
    pub fn export_transcript(&self) -> SessionTranscript;   // 整份快照
}
```

`SessionTranscript`、`TranscriptMessage` 与 `ContentBlock` 都派生了 `Serialize`/`Deserialize`，可直接过 `serde_json`。

## 可运行代码

```rust
use brainary_agent_sdk::{BrainaryClient, Options};
use futures::StreamExt;

let mut client = BrainaryClient::connect(options).await?;

// 跑一两轮，累积上下文
{
    let mut stream = client.query("查一下东京天气");
    while let Some(item) = stream.next().await { let _ = item?; }
}   // 流作用域结束、释放 &mut 借用

// 导出只读快照并序列化
let transcript = client.export_transcript();
let json = serde_json::to_string_pretty(&transcript)?;
println!("{json}");
```

### 预期输出（形态）

```json
{
  "messages": [
    { "role": "system",    "content": [ { "type": "text", "text": "..." } ] },
    { "role": "user",      "content": [ { "type": "text", "text": "查一下东京天气" } ] },
    { "role": "assistant", "content": [ { "type": "text", "text": "东京今天..." } ] }
  ]
}
```

`content` 里的块用 `type` 标签区分（`text` / `tool_use` / `tool_result` / `thinking`），v1 只会出现 `text`。

## 映射：llmy 上下文 → SDK 自有类型

`export_transcript()` 把 llmy 的 `conversation_context()`（内部是 async-openai 的 `RawExtensibleChatRequestMessage`）映射为 SDK 自有的 `TranscriptMessage`：

- 每条消息取其 wire 形态（OpenAI chat 消息 `{"role": ..., "content": ...}`）的 `role` 与 `content` 两个字段。
- `content` 是裸字符串 → 一个 `Text` 块；是 `{type,text}` 数组 → 逐个 `text` 部分各成一个 `Text` 块。
- **非文本内容降级**：llmy 未结构化透出的内容（工具调用、图片等）在 v1 里**降级或丢弃**——按设计是「有损到文本」，忠实反映 v1 能读到的东西。
- 全程**不外泄 llmy 类型**：调用方只碰 SDK 自有、可序列化的类型。

## ⚠️ 仅导出，不可续跑

transcript 是 **export only**：

- llmy **没有**「用历史重建 agent」的构造器，所以一份 transcript 在 v1 里**无法被 resume 回一个运行中的 agent**。
- 进程内的多轮 resume 由 `BrainaryClient` 保留 agent 状态天然支持；但**跨进程的真 resume**（把导出的 transcript 载入新进程继续跑）归 **M5**。

细节与排期见 [v1 边界与路线图](/sdk/limits)。

## 相关

- [query 与 client](/sdk/query-and-client) —— `BrainaryClient` 多轮状态与借用作用域
- [消息模型](/sdk/messages) —— `ContentBlock` 四类块与 v1 填充度
- [v1 边界与路线图](/sdk/limits) —— 跨进程 resume（M5）
