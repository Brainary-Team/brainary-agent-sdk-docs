---
outline: 2
---

# SDK 总览

> **读完本页你能**：知道 `brainary-agent-sdk` 是什么、为什么它是应用开发者的默认入口，看懂两个宿主内入口的取舍（以及第三个、跑沙箱 PoA 的入口）与 v1 的能力填充度，并找到本章各页的入口。

`brainary-agent-sdk` 是 brainary-rs 的**高层门面 crate**。它把「装配好的 Agent」浓缩成几行调用：一个 `query()` 跑一次性任务，一个 `BrainaryClient` 跑有状态多轮，全部行为收敛到一个 `Options` 配置对象和一条步级 `Message` 流上——你**无需直接接触底层 llmy 类型**。

## 三层里的第一层

brainary-agent-sdk 叠在 brainary-core 之上，是应用开发者应当默认使用的一层：

| 层 | crate | 面向 | 你在这里做什么 |
| --- | --- | --- | --- |
| tier-1 | **brainary-agent-sdk** | 应用开发者（默认入口） | `query` / `BrainaryClient` / `Options` / `Message` |
| tier-2 | brainary-core | 需要自定义装配的进阶用户 | `BrainaryAgentBuilder` / `BrainaryPrimitive` |
| tier-3 | llmy | 底层 LLM 客户端 | 一般不直接触碰 |

只要在 `Cargo.toml` 里依赖 `brainary-agent-sdk` 一行即可——错误类型、prelude、`#[tool]` 宏、`Decimal`/`LLMSettings`/`AgentConfig` 等都经 SDK re-export（见 [Options](/sdk/options)）。

> 例外：**用 `#[tool]` 宏自己写工具**时，除 `brainary-agent-sdk` 外还须直接依赖 `llmy`（宏按 crate 名解析路径）与 `schemars`/`serde`。原因与写法见 [自定义工具 FunctionTools](/sdk/tools)。

## 接口一览：命名与状态 {#interface-overview}

brainary-agent-sdk 的接口面按「Brainary-Code-like agent SDK」这一目标工具的视角裁剪而来。下表把各接口的命名、状态与文档落点汇成一览；每一项的详情落在对应页：

| Brainary（Rust） | 状态 | 去哪页 |
| --- | --- | --- |
| `query()` | 🟠 | [两个入口](/sdk/query-and-client) |
| `BrainaryClient` | 🟠 | [两个入口](/sdk/query-and-client) |
| `Options`（`Options::builder()`） | 🟠 | [Options](/sdk/options) |
| `#[tool]` / `FunctionTools` | 🟠 | [自定义工具](/sdk/tools) |
| `Message` / `ContentBlock` | 🟠 | [消息模型](/sdk/messages) |
| `InterruptHandle::interrupt()`（句柄） | 🟠 | [中断与护栏](/sdk/interrupt-and-guardrails) |
| 内置工具目录（read_file/write_file/…，原生名） | 🟠 | [内置工具目录](/sdk/builtin-tools) |
| `list_sessions()` / `rename_session()` 等 | 🟠 | [会话管理](/sdk/sessions) |
| `CanUseTool` / `PermissionMode`（6 模）/ `allowed_tools` | 🟠 | [权限模型](/sdk/permissions) |
| `hooks`（PreToolUse 等生命周期钩子） | 🟠 | [Hooks](/sdk/hooks) |
| `BrainaryError` 枚举 + `ErrorCategory` | 🟠 | [错误处理](/sdk/errors) |
| `Options.agents`（子 agent，SDK 一等面） | 🟠 | [Options](/sdk/options) · 构建 Agent |

> 全表接口均为 🟠【规划中，未完成】——架构已规划、尚未实现。先落接口占位（含建议性 Rust 签名）是因为它们是**架构上该有**的面，便于后续对齐讨论；判断依据见 [边界与路线图](/sdk/limits) 的覆盖矩阵。

## 两个入口

| 入口 | 语义 | 流生命周期 |
| --- | --- | --- |
| `query(prompt, options)` | 一次性；每次新建 agent，等价「开一个新会话」 | `'static`（流自持 agent） |
| `BrainaryClient::connect(options).await?` 后 `client.query(prompt)` | 有状态多轮；进程内保留上下文（原生 resume） | `'_`（借 `&mut self`） |

两者共用同一套 `Options`、同一条 `Message` 流。细节与代码见 [两个入口](/sdk/query-and-client)。

> **还有第三个、另一类入口**：`poa` feature 后的 `PoaRunner`——它不驱动宿主内 agent，而是把一个沙箱化的 PoA（`.poa` 程序）跑起来。这以前是 CLI 独占（`brainary run`），现在也能库调用。off-by-default，基线 `query()` 用户不背 wasm 运行时依赖。见 [运行一个 PoA](/sdk/running-a-poa)。

## 能力梯队

从最少的代码开始，按需逐档加码，每一档都对应本章一页：

| 档位 | 你要做的 | 去哪页 |
| --- | --- | --- |
| 三行起步 | `Options::builder().model(...).build()?` + `query(...)` | 快速上手 |
| 配置 | 模型、系统提示、内置能力糖、逃生口 | [Options](/sdk/options) |
| 消费消息流 | `AssistantMessage` / `ResultMessage` / `StopReason` | [消息模型](/sdk/messages) |
| 自定义工具 | `#[tool]` + `FunctionTools` | [自定义工具](/sdk/tools) |
| 中断与护栏 | `InterruptHandle`、`max_turns`、上下文溢出 | [中断与护栏](/sdk/interrupt-and-guardrails) |
| 会话导出 | `export_transcript()` 只读快照 | [会话导出](/sdk/transcript) |
| 运行一个 PoA | `poa` feature + `PoaRunner` 库调用跑 `.poa` | [运行一个 PoA](/sdk/running-a-poa) |
| 边界与限制 | v1 明确不做的项、受 llmy 限制的项 | [能力边界](/sdk/limits) |

## 状态说明 {#capability-fill}

本 SDK **全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；本章给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非可用实现。

**状态图标图例**（全站统一，权威定义见 [能力边界](/sdk/limits)）：

| 图标 | 含义 |
| --- | --- |
| 🟢 | **已完成，可用**——已实现并可正常调用 |
| 🟠 | **规划中，未完成**——纳入本站交付面；架构与签名已规划、尚未实现 |
| ⬇️ | **下沉核心层**——非本站门面职责，归 core 层 |
| ⚪ | **暂缓 / 不纳入**——仅登记（附理由），非交付接口 |

当前**全部纳入面一律为 🟠**（尚无 🟢），不再细分实现档位。

各消息字段的规划填充度见 [消息模型](/sdk/messages)，边界裁决见 [能力边界](/sdk/limits)。

## 三行起步引子

```rust
// 只需依赖 brainary-agent-sdk 一个 crate，全部类型都从这里取（见「三层里的第一层」）。
use brainary_agent_sdk::{query, Message, ModelSelection, Options};
// query() 返回一条异步流；.next() 方法由 StreamExt 提供，故需要引入此 trait。
use futures::StreamExt;

// 1) 组装配置。Options 是唯一的配置对象，所有行为都收敛到它上面。
let options = Options::builder()
    // 从环境变量读取模型接入信息：OPENAI_API_KEY / OPENAI_API_MODEL / OPENAI_API_URL。
    // 三者缺一即在此处 ? 上抛错误——所以务必先设置好环境变量（见下方「快速上手」）。
    .model(ModelSelection::from_env()?)
    .enable_memory(true)   // 打开内置记忆能力糖；更多配置项见 [Options](/sdk/options)。
    .build()?;             // 定型为不可变的 Options；配置非法（如缺模型）在此报错。

// 2) 发起一次性任务。query() 每次新建一个 agent 并立即返回步级 Message 流,
//    流本身持有 agent（'static），无需你手动管理生命周期。
let mut stream = query("介绍一下你自己。", options).await?;

// 3) 逐条消费消息流，直到流结束（.next() 返回 None）。
while let Some(item) = stream.next().await {
    // item 的类型是 Result<Message, _>：单步失败会作为流的 Err 抛出,
    // 这里用 ? 把它上抛；成功则拿到一个 Message。
    // 只关心助手回复，用 if let 过滤出 Message::Assistant 这一种变体。
    if let Message::Assistant(a) = item? {
        println!("{a:?}");   // a 是 AssistantMessage；字段含义见 [消息模型](/sdk/messages)。
    }
    // 其他变体（如 Message::Result 收尾摘要）在此被忽略；完整消费方式见「消息模型」。
}
```

完整的环境准备与运行步骤见 快速上手。

## 下一步

- [接口索引](/sdk/api-index) —— 按 Functions / Classes / Types 反查接口的状态与落点
- [示例用法](/sdk/examples) —— 四段完整程序：一次性 / 错误处理 / 流式多轮 / 配合自定义工具
- [两个入口：query() 与 BrainaryClient](/sdk/query-and-client)
- [运行一个 PoA（poa feature）](/sdk/running-a-poa)
- [Options 统一配置](/sdk/options)
- [消息模型](/sdk/messages)
- [内置工具目录](/sdk/builtin-tools) —— SDK 开箱自带、可被模型调用的工具目录
- [自定义工具 FunctionTools](/sdk/tools) · [错误处理](/sdk/errors)
- 进阶（架构已规划）：[会话管理](/sdk/sessions) 🟠 · [权限模型](/sdk/permissions) 🟠 · [Hooks](/sdk/hooks) 🟠
- [边界与路线图](/sdk/limits) —— 覆盖矩阵：接口全表面与决策
