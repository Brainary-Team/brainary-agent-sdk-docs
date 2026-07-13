---
outline: 2
---

# 轻量自定义工具（FunctionTools）

> **读完本页你能**：用一个 `#[tool]` 函数写出一个工具，把一组工具打包成一个命名能力单元 `FunctionTools`，挂进 `Options`，并理解它的依赖约束与构建期校验。

## 概念简述

在 brainary-rs 里，能力的打包单元叫 **primitive**（见 核心 primitive）。写一个完整 primitive 需要手动实现 `BrainaryPrimitive` 的四个方法；多数时候你只想「加几个函数当工具」而已。

`FunctionTools` 就是这条捷径：

- **一个 `#[tool]` 函数 = 一个工具**。
- **一组工具 = 一个命名能力单元**（namespace + 描述 + 可选模板变量）。
- 它内部就是一个**薄薄的 `BrainaryPrimitive`**——把你的 `#[tool]` 工具箱包起来，其余的面（命名空间、变量注入、构建期校验）由 SDK 补齐。

形态上：单个函数是工具，一组是一个命名单元。

## 核心 API

`FunctionTools` 的方法签名（来自 `crates/brainary-agent-sdk/src/tools.rs`）：

| 方法 | 签名 | 作用 |
| ---- | ---- | ---- |
| `FunctionTools::new` | `new(name: impl Into<String>, description: impl Into<String>) -> Self` | 开一个命名单元，`name` 即其系统提示命名空间 |
| `.add` | `add<T: Tool + 'static>(self, tool: T) -> Self` | 追加一个 `#[tool]` 生成的工具（可链式） |
| `.variables` | `variables(self, variables: Value) -> Self` | 设定注入本命名空间的模板变量（默认 `null`） |
| `.len` / `.is_empty` | `-> usize` / `-> bool` | 本单元贡献了几个工具 |

挂进配置：`Options::builder().extra_tools(function_tools)`（可多次调用，累积多个单元）。

## 可运行代码

```rust
use brainary_agent_sdk::{FunctionTools, ModelSelection, Options};
// #[tool] 宏经 SDK re-export；但参数类型的 schema/serde 派生仍需工具作者自带依赖
use brainary_agent_sdk::tool;               // = llmy::agent::tool
use llmy::LLMYError;
use schemars::JsonSchema;
use serde::Deserialize;

/// 工具的参数类型：字段文档注释会进入模型看到的 JSON Schema。
#[derive(Debug, Deserialize, JsonSchema)]
struct WeatherArgs {
    /// 城市
    city: String,
}

#[derive(Clone, Debug)]
#[tool(
    arguments = WeatherArgs,    // 参数类型：模型回传的 JSON 反序列化成它
    invoke = run,               // 工具被调用时执行下方 impl 里的 `run` 方法
    name = "get_weather",       // 模型看到的工具名,须在本 agent 内全局唯一
    description = "查询城市当前天气"  // 模型看到的工具说明
)]
struct GetWeather;              // 无状态工具用单元结构体即可；需持有状态就改成带字段的 struct

impl GetWeather {
    // `invoke = run` 指向的执行体：返回 Ok(String) 即工具输出(回填给模型),Err 作为工具错误上报。
    async fn run(&self, args: WeatherArgs) -> Result<String, LLMYError> {
        Ok(format!("{} 天气晴", args.city))
    }
}

// 一组工具 = 一个命名能力单元
let weather = FunctionTools::new("weather", "天气查询能力")
    .variables(serde_json::json!({ "enable_weather": true }))  // 模板可 gate 的变量
    .add(GetWeather);

assert_eq!(weather.len(), 1);

let options = Options::builder()
    .model(ModelSelection::from_env()?)
    .extra_tools(weather)              // 挂进配置
    .build()?;
```

### 预期行为

`weather` 单元会以命名空间 `weather` 进入 agent：它向模型贡献 `get_weather` 工具，并向系统提示模板注入变量 `{ "enable_weather": true }`（模板可用 `{% if weather.enable_weather %}` 之类门控）。`.len()` 返回 `1`。

## ⚠️ 依赖约束：写 `#[tool]` 的 crate 必须直接依赖 `llmy`

这是复用 llmy 工具宏的**固有约束**，不是 SDK 的选择：

- `#[tool]` 宏用 `proc_macro_crate` **按 crate 名解析路径**，展开后引用的是 `llmy::...`。因此写 `#[tool]` 的 crate 的 `Cargo.toml` 里**必须直接有 `llmy` 依赖**（`use brainary_agent_sdk::tool` 只能拿到宏本身，解决不了宏展开体里对 `llmy` 路径的引用）。
- 参数类型（这里的 `WeatherArgs`）是**工具作者自有的类型**，其 `#[derive(Deserialize, JsonSchema)]` 需要 `serde` 与 `schemars`。这两个也要在你的 `Cargo.toml` 里。

`Cargo.toml` 至少要有：

```toml
[dependencies]
# brainary-agent-sdk 仅内部使用、不发布到 crates.io，经 git 引入（仓库地址向团队获取）
brainary-agent-sdk = { git = "<brainary-rs 仓库地址>" }
llmy = "0.16"                      # #[tool] 宏按名解析路径的必需项（公开 crate）
schemars = "1"                     # 参数类型的 JsonSchema 派生（须与 llmy 一致）
serde = { version = "1", features = ["derive"] }
serde_json = "1"                   # 构造 variables / 参数
```

> 除了这条约束，SDK 负责其余全部面：调用方只依赖 `brainary-agent-sdk` 一行即可拿到 `query` / `BrainaryClient` / `Options` / 错误类型 / prelude。

## 命名空间进入构建期校验

`FunctionTools` 作为薄 primitive，和内置 primitive 一样进入 builder 的**构建期**校验：

- 工具重名 → `DuplicateTool`
- 命名空间（变量名）撞名 → `DuplicateVariableName`

也就是说：两个单元里都有 `get_weather` 工具、或两个单元都叫 `weather`，会在 `Options::builder().build()` 之后组装 agent 时**立即报错**，而不是运行到一半才炸。这与核心层裸 builder 的行为一致。

## MCP：另一类工具来源

除了 `#[tool]` 写的本地函数工具，agent 的工具还能来自 **MCP 服务**——一个 MCP server 暴露的工具会作为一类 primitive 挂进 agent：

| 能力 | Brainary v1 | 状态 |
| --- | --- | --- |
| 挂载一个 MCP server | `Options::builder().mcp_server(url)`（糖，可多次调用累加） | 🟢 |
| 富配置（Stdio / SSE / Http 传输、鉴权头等） | 目前糖只收 URL 字符串 | 🟡 待扩 |
| 运行时控制（`get_mcp_status` / `reconnect` / `toggle`） | — | 🟠 未实现 |

v1 里最小接法就是一行糖：

```rust
let options = Options::builder()
    .model(ModelSelection::from_env()?)
    .mcp_server("https://host/mcp")   // 该 server 暴露的工具进入 agent
    .build()?;
```

MCP 服务端契约（必须暴露可解析的 `brainary` 资源）与接入细节见 MCP 接入；MCP 运行时控制的排期见 [边界与路线图](/sdk/limits)。

## ToolAnnotations：工具行为提示（架构占位）

::: warning 架构已规划、尚未实现（🟠）
`ToolAnnotations` 给每个工具附带行为提示（`readOnly` / `destructive` / `idempotent` / `openWorld`），供权限层与 UI 判断「这个工具危不危险」。Brainary v1 **未实现**这一层；下面是接口占位，签名待定。
:::

这些提示的用途是让 [权限模型](/sdk/permissions) 能自动决策（如「只读工具自动放行、破坏性工具问一次」）。规划形态（草案）：

```rust
// ⚠️ 架构占位，v1 未实现、签名待定。
pub struct ToolAnnotations {
    pub read_only: bool,     // 只读，不改外部状态
    pub destructive: bool,   // 可能造成不可逆副作用
    pub idempotent: bool,    // 同样入参重复调用结果一致
    pub open_world: bool,    // 触达外部/开放世界（网络等）
}
// 规划：在 #[tool(...)] 宏里以属性声明，如 #[tool(read_only, ...)]
```

在它落地前，v1 对工具「危不危险」没有结构化标注——控制手段只有装配期的「装/不装」（见 [权限模型](/sdk/permissions#与装配期手段的关系)）。

## 与完整 primitive 的关系

`FunctionTools` 是**薄 primitive**——只覆盖「一组函数工具 + 一个命名空间 + 可选变量」这一常见场景。如果你需要：

- 更复杂的状态、生命周期资源（如连接）、动态工具集，
- 或想完全自定义 `BrainaryPrimitive` 的四方法契约，

请写完整 primitive，用 `Options::builder().extra_primitive(Box::new(my_prim))` 逃生口挂入。完整 primitive 的接口与内置目录见 核心 primitive 与 primitive 目录。

## 相关

- [Options 配置](/sdk/options) —— `extra_tools` / `extra_primitive` 与其它糖字段
- [消息模型](/sdk/messages) —— 工具调用在 v1 的填充度（`requested_tools` 粗信号，结构化块待上游）
- [权限模型](/sdk/permissions) —— 谁能调哪个工具（架构已规划）
- [v1 边界与路线图](/sdk/limits) —— 结构化 `tool_use` / `tool_result` 填充的排期
