---
outline: 2
---

# 错误处理

> **读完本页你能**：知道 SDK 里错误从哪来、怎么接（流的 `Err` 通道 vs 构建期 `Result`），认全你在 SDK 层实际会撞到的几类 `BrainaryError`，会用 `category()` 按恢复策略分支，并知道去哪查完整错误目录。

错误处理是会议点名的必备面。Rust 侧的错误模型是**一个 `#[non_exhaustive]` 枚举 `BrainaryError`**（已带 **7 个变体** + 构建期领域错误，比「一个 opaque error」细得多），错误从两个明确的位置冒出来，你不用猜。

> **跨语言同一模型、各用本地惯用法**：Rust 是「一个枚举 + [`category()` 访问器](#按恢复策略分支-errorcategory)」；Python 是「一棵异常子类树」（`BuildError` / `RateLimitError` / `ToolExecutionError` …，`except 具体子类` 直接分支）。见 [Python：错误处理](/sdk-py/errors)。

## 错误从哪来：两个位置

| 位置 | 形态 | 什么时候 |
| --- | --- | --- |
| **构建期** | `Options::builder().build()` / `connect()` 返回 `Err` | 配置有问题：缺 `model`、工具重名、命名空间冲突、模板语法错——**发任何模型请求之前**就报 |
| **运行期** | 消息流的某一项是 `Err(BrainaryError)` | 单步执行失败：模型调用出错、工具执行抛错、MCP 故障等 |

这两处都返回同一个错误类型 `BrainaryError`（与 core 共用），都能直接用 `?` 上抛。

## 运行期：错误走流的 Err 通道

步级 `Message` 流的每一项是 `Result<Message>`。错误**不是**一种停机原因（`StopReason` 里没有 `Error` 变体），而是走流的 `Err` 通道——一旦某步失败，流产出一个 `Err` 然后结束：

```rust
use brainary_agent_sdk::{query, Message, ModelSelection, Options};
use futures::StreamExt;

let options = Options::builder().model(ModelSelection::from_env()?).build()?;
let mut stream = query("介绍一下你自己。", options).await?;

while let Some(item) = stream.next().await {
    match item {
        Ok(Message::Result(r)) => println!("正常停机：{:?}", r.stop_reason),
        Ok(_msg) => { /* 其余消息 */ }
        Err(e) => {
            eprintln!("运行出错：{e}");   // e: BrainaryError
            break;                        // 流已结束，跳出
        }
    }
}
```

想省事就直接 `?`：`while let Some(item) = stream.next().await { let msg = item?; /* … */ }`——单步错误会作为函数的 `Err` 上抛。

> **正常终局 vs 出错是两条正交的通道**：`Ok(Message::Result)` 是「跑完了，这是为什么停」；`Err` 是「中途炸了」。所以你**永远不会**在 `ResultMessage` 里读到「出错了」的布尔——`is_error` 在 v1 恒为 `false`。详见 [消息模型](/sdk/messages#错误模型-流的-err-与终局-result-正交)。

## 构建期：配置错误当场报

配置类问题在 `build()` / `connect()` 就返回 `Err`，不会拖到运行期。你在 SDK 层最常撞到的是这几类：

| 错误信息片段 | 含义 | 怎么修 |
| --- | --- | --- |
| 含 `"model"` | 忘了设必填的 `model` | `Options::builder().model(...)` |
| `duplicate tool name ... across primitives` | 两个工具/单元暴露了同名工具 | 改工具 `name` 保证全局唯一 |
| `duplicate variable namespace ...` | 两个 primitive/`FunctionTools` 命名空间撞名 | 改其一的 `name` |
| `variable namespace "global" is reserved` | 某能力单元命名为保留字 `global` | 换个名字 |
| `template error: ...` | 系统提示 Jinja2 模板语法/求值错 | 检查 `inline_prompt` / `template_file` 内容 |
| `MCP server ... did not expose a parseable brainary resource` | 接入的 MCP 服务未暴露可解析的 `brainary` 资源 | 见 MCP 接入 |

这些都来自 `FunctionTools` / primitive 的**构建期校验**（见 [自定义工具](/sdk/tools#命名空间进入构建期校验)）。

## 你实际会用到的：区分底层与领域错误

`BrainaryError` 有两个辅助方法，用来区分「底层 llmy 错误」与「brainary 自身的领域错误」：

```rust
use brainary_agent_sdk::BrainaryError;

match result {
    Ok(_) => { /* … */ }
    Err(BrainaryError::DuplicateTool(name)) => {
        eprintln!("工具重名：{name:?}");
    }
    Err(err) => {
        if let Some(llmy_err) = err.as_llmy() {   // 是底层 llmy 错误则借出内部
            eprintln!("底层出错：{llmy_err}");
        } else {
            eprintln!("其他：{err}");
        }
        // BrainaryError 是 #[non_exhaustive]，跨 crate match 需带 _ 臂（这里由外层 Err(err) 兜底）
    }
}
```

`BrainaryError` 经 `brainary-agent-sdk` re-export（`brainary_agent_sdk::BrainaryError`），无需另加依赖。

## 按恢复策略分支：`ErrorCategory`（🟠 规划） {#按恢复策略分支-errorcategory}

`as_llmy()` 只区分「底层 vs 领域」，但当你想对**运行期**失败按恢复动作分支时（鉴权失败别重试、限流退避重试、5xx 可重试…），逐个 match llmy 内层字符串太脆。规划中给 `BrainaryError` 一个 `category()` 访问器，把失败归入一组稳定的**可恢复性类别**：

```rust
// 🟠 架构已规划、未实现。enum 保持小 + #[non_exhaustive]，恢复策略靠 category() 分支。
#[non_exhaustive]
pub enum ErrorCategory {
    Config,          // 构建期配置/装配错（DuplicateTool 等）
    Auth,            // 鉴权失败 —— 修 key，别重试
    Billing,         // 计费/额度 —— 停，报人
    RateLimit,       // 限流 —— 退避后重试
    InvalidRequest,  // 请求非法 —— 调用方 bug
    ServerError,     // 供应商 5xx —— 可重试
    Timeout,         // 超时 —— 可重试
    MaxTokens,       // 触顶 max_output_tokens —— 加预算/续跑
    Tool,            // 某个工具自身抛错
    Other,
}

impl BrainaryError {
    pub fn category(&self) -> ErrorCategory { /* … */ }
}
```

```rust
match err.category() {
    ErrorCategory::RateLimit => retry_after_backoff(),
    ErrorCategory::Auth      => bail!("检查 key"),   // 别重试
    _                        => return Err(err),
}
```

这组类别与步级 [`AssistantMessageError`](/sdk/messages#assistant-message-error) 的分类同源，也**一一对应 Python 侧的异常子类**（`RateLimit` ⟷ `RateLimitError`，`Config` ⟷ `BuildError` …）——见 [Python：错误处理](/sdk-py/errors)。它把「可分支恢复」的意图，用 Rust 枚举惯用法落下。

## 不纳入的：`CLI*Error` 一族（OUT） {#cli-error-family-out}

`CLINotFoundError` / `CLIConnectionError` / `ProcessError`(exit_code/stderr) / `CLIJSONDecodeError` 这几类异常**不进** `BrainaryError`。它们是 **CLI 子进程传输方式的副作用**（找不到二进制、连不上子进程、子进程非零退出、解析不了它吐的 JSON 行），不是错误设计。brainary-agent-sdk 是**进程内库**，没有子进程/二进制/JSON 管线这一层，照抄等于进口别人的传输事故。处置详见 [边界与路线图 · 覆盖矩阵](/sdk/limits#coverage-matrix)。

## 完整错误目录

`BrainaryError` 是 SDK 与 core 共用的**同一个**枚举，共 7 个变体。SDK 层通常只需上表那几类；**完整变体清单、`#[from]` 透传规则、辅助方法与排错速查**见核心层参考：

- 类型与错误参考 —— `BrainaryError` 全 7 变体 + `Result<T>` 约定 + 排错速查表

## 相关

- [消息模型](/sdk/messages#错误模型-流的-err-与终局-result-正交) —— 错误走 `Err`、与 `StopReason` 正交
- [自定义工具 FunctionTools](/sdk/tools#命名空间进入构建期校验) —— 构建期工具/命名空间校验
- [边界与路线图](/sdk/limits)
