---
outline: 2
---

# 运行一个 PoA（`poa` feature）

> **读完本页你能**：知道除 `query()` / `BrainaryClient` 外的**第三个宿主入口** `PoaRunner` 是什么、什么时候用它，用几行代码从宿主内库调用跑起一个 `.poa`，并看懂它的返回值与几个装配旋钮。
>
> 源：`crates/brainary-agent-sdk/src/poa.rs`（`poa` feature）。

::: warning brainary-agent-sdk 尚未合并进主干
本页描述的 `PoaRunner` 属于 `brainary-agent-sdk`，目前在**独立开发分支**上开发、尚未合并进主干；本页按「已合并」处理。合并前，`crates/brainary-agent-sdk/` 尚不可见，`.poa` 只能用 `brainary run` CLI 跑。文中源码路径均以合并后为准。
:::

## 它是什么：第三个入口

SDK 有[两个宿主入口](/sdk/query-and-client) `query()` 与 `BrainaryClient`——两者都在**宿主内**驱动一个 in-host agent。`PoaRunner` 是第三个、也是**另一类**入口：它不驱动 in-host agent，而是把一个 **PoA**（编译成 wasm 的沙箱程序 + manifest）跑起来，让它经一条 syscall 边界从**沙箱内**驱动同一台 core 引擎。

| 入口 | 驱动什么 | 谁定义 agent |
| --- | --- | --- |
| `query()` / `BrainaryClient` | 宿主内 in-host agent | 你，用 `Options` 塑形 |
| `PoaRunner` | 沙箱外的 `.poa` 程序 | **PoA 自带**（模板、primitive 都在包里） |

一句话取舍：**跑你自己在宿主内组装的 agent → 用 `query()` / `Client`；跑一个别人写好、以一个文件分发的沙箱程序 → 用 `PoaRunner`。** 二者的架构取舍见「SDK 还是 PoA」选型指南。

这以前是 **CLI 独占**能力（`brainary run`）；`PoaRunner` 把它变成一次库调用。CLI 的 `run` 如今也**吃自己的狗粮**——它内部就是驱动这同一个 `PoaRunner`。

::: tip 它在 `poa` feature 后面
整个 `poa` 模块由 off-by-default 的 `poa` feature 门控：打开它会拉入 `brainary-kernel`，连带 wasm 运行时（wasmtime）。基线 `query()` 用户**不会**背上这些依赖。

```toml
# Cargo.toml
brainary-agent-sdk = { version = "*", features = ["poa"] }
```
:::

## 最小示例

```rust
use brainary_agent_sdk::poa::PoaRunner;
use brainary_agent_sdk::{ModelSelection, Options};

# async fn demo() -> brainary_agent_sdk::Result<()> {
// 1) 宿主提供模型凭证；PoA 自带 agent，所以只用得到 Options 的模型/账单/调试字段。
let options = Options::builder().model(ModelSelection::from_env()?).build()?;
let llm = brainary_agent_sdk::poa::build_llm(&options).await?;

// 2) 命名一个待跑的 PoA。new() 很廉价：不做任何 I/O，也不返回 Result。
let outcome = PoaRunner::new("weather.poa")
    .run(llm)          // 所有 I/O 都发生在这里
    .await?;

// 3) outcome.result 是 PoA 的返回串；outcome.report 是本次运行统计。
println!("{}", outcome.result.as_deref().unwrap_or("(none)"));
println!(
    "calls={} dur={:.1}s cancelled={}",
    outcome.report.calls,
    outcome.report.duration.as_secs_f64(),
    outcome.report.cancelled,
);
# Ok(())
# }
```

## 惰性构造：先失败，再花钱

`PoaRunner::new(...)` **不碰文件系统**，直接返回 `Self`（不是 `Result`）。所有会失败的步骤——打开 / 解压 `.poa`、装配 primitive registry、建 kernel、执行——全部推迟到 `.run(llm).await` 里。

所以打包类错误**仍然先于任何 LLM 调用**暴露（框架的「先失败、再花钱」原则），只是落点从「构造时」挪到了 `run().await?` 的第一个 `?`。

## `build_llm`：复用 SDK 的模型接入

`build_llm(&options)` 走的是 `query()` / `BrainaryClient` **完全相同**的 LLM 构造路径。因为 PoA 自带 agent（模板、primitive 都在包里），它**只读** `Options` 的**模型 / 账单上限 / LLMSettings / 调试**字段——塑形 agent 的那些 `Options` 字段在这里无关。

返回的 `LLM` 句柄 clone 廉价，可以驱动**多次** `run()` 调用（跑多个 `.poa` 复用同一凭证）。

## 装配旋钮

`new()` 之后、`run()` 之前，用链式 builder 方法调整；每个都返回 `Self`：

| 方法 | 作用 |
| --- | --- |
| `.output_dir(dir)` | `.poa` 压缩包的解压目标：给了就解压到这里并**保留**（可进去检查）；不给则用临时目录、跑完自动清理。**目录形式的 PoA 忽略此项**。 |
| `.journal(path)` | 落一份每个 syscall 的 JSONL 审计——本次运行的 strace，便于排查 / 回放。 |
| `.extra_primitive(p)` | 注入一个 manifest 之外的**宿主侧 primitive**，对程序与其 agent 都可见（`Visibility::Both`，与 CLI 对 `memory` / MCP primitive 的处置一致）。 |
| `.extra_primitive_with_visibility(p, vis)` | 同上，但显式指定 [`Visibility`](#visibility)（逃生口，用于需要 `ProgramOnly` / `AgentVisible` 的场景）。 |

宿主注入的 extras **最后注册**，可有意覆盖 manifest 里的同名能力。

**`Visibility`** —— 注入 primitive 对「程序」与「其 agent」的可见性（`extra_primitive` 默认 `Both`）：{#visibility}

```rust
#[non_exhaustive]
pub enum Visibility {
    Both,          // 程序与 agent 都可见（默认）
    ProgramOnly,   // 仅 .poa 程序可见，agent 看不到
    AgentVisible,  // 仅 agent 可见
}
```

```rust
use brainary_agent_sdk::poa::{PoaRunner, Visibility};

# async fn demo(llm: brainary_agent_sdk::poa::LLM, my_primitive: impl brainary_agent_sdk::BrainaryPrimitive + 'static) -> brainary_agent_sdk::Result<()> {
let outcome = PoaRunner::new("weather.poa")
    .output_dir("./unpacked")            // 解压并保留，便于检查
    .journal("weather.jsonl")            // 落 syscall 审计
    .extra_primitive(my_primitive)       // 注入宿主侧能力，程序 + agent 都可见
    .run(llm)
    .await?;
# let _ = outcome; Ok(())
# }
```

## 返回值：`PoaOutcome`

`run()` 成功返回 `PoaRun`（别名 `PoaOutcome`，为读起来顺）——它就是 kernel 自己的运行结果类型，SDK **原样 re-export**（单一真源，不是平行结构体）：

```rust
pub struct PoaRun {          // = PoaOutcome，#[non_exhaustive]
    pub result: Option<String>,   // PoA entry 的返回串（常是 JSON），无返回则 None
    pub report: RunReport,
}

pub struct RunReport {       // #[non_exhaustive]
    pub calls: u64,               // syscall 次数
    pub duration: Duration,       // 本次运行耗时
    pub cancelled: bool,          // 是否被 Ctrl-C 取消
}
```

两者都是 `#[non_exhaustive]`：构造靠 `run()`，你只读字段，不 `match { .. }` 穷举——上游加字段不破坏你的代码。这和 CLI `brainary run` 打印的 `=== Result ===` / `=== Run report ===` 是同一份数据（见 CLI 输出）。

## 下一步

- [两个入口：query 与 Client](/sdk/query-and-client) —— 另两个（宿主内 agent）入口
