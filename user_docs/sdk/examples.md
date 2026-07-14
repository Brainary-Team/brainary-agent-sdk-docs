---
outline: 2
---

# 示例用法

> **读完本页你能**：照抄四段**完整**示例程序（规划形态，接口落地后可运行）,分别覆盖一次性任务、错误处理、有状态多轮、以及配合自定义工具。

这四段是把前面各页的概念**拼成整段程序**的样板。每段规划为可独立运行（接口落地后）,届时只需先备好环境变量(见 快速上手);概念细节在每段末尾给出去处。

> 下面的片段都写在某个 `async fn` 体内(省略了外层 `#[tokio::main]` / 函数包装)。

## 基础文件操作:内置工具(用 query)

**基础文件操作**:开箱启用内置工具套件,给一个文件任务,让 agent **自行调用**内置文件工具(`read_file` / `write_file` …)。要点先说清:内置工具是**模型在 agent 循环里调用**的,你不直接调它们——你的动作是「**启用 + 授权 + 给会触发它们的 prompt**」这三件事。文件这一组底层由 `FolderPrimitive` 提供(🟠);完整目录与 schema 见 [内置工具目录](/sdk/builtin-tools),工具也可来自自定义 [`FunctionTools`](/sdk/tools) 或 MCP。

```rust
use brainary_agent_sdk::{query, Message, ModelSelection, Options};
use futures::StreamExt;

// 1) 启用内置工具套件:read_file / write_file / edit_file / find_file / grep …
//    一键装上后,模型在 agent 循环里【自行调用】它们(你不直接调)。
let options = Options::builder()
    .model(ModelSelection::from_env()?)
    .enable_default_tools(true)                     // 一键装上标准内置工具套件;文件工具由 FolderPrimitive 提供(🟠)
    .allowed_tools(["read_file", "write_file"].map(String::from))  // 这两个免确认放行;其余落到 permission_mode / can_use_tool
    .build()?;

// 2) 给一个会触发文件工具的任务:调不调、怎么调由模型决定
let mut stream = query("读取 ./notes.md,把要点浓缩成三行,写回 ./summary.md。", options).await?;

// 3) 逐条消费:v1 只回填 Text 块;模型实际发起的 ToolUse/ToolResult 块
//    类型已就位、暂不透出(🟠),故这里读到的是最终文本结论
while let Some(item) = stream.next().await {
    match item? {
        Message::Assistant(a) => println!("assistant: {a:?}"),
        Message::Result(r) => println!("停机原因:{:?}", r.stop_reason),
        _ => {}   // Message 是 #[non_exhaustive],match 必带 _ 臂
    }
}
```

**这段演示**:开箱启用内置工具、`allowed_tools` 授权、以及 agent 自行调用文件工具的一问一答语义。工具的授权与命令沙箱见 [权限模型](/sdk/permissions);目录与逐工具 schema 见 [内置工具目录](/sdk/builtin-tools);消息块的 v1 填充度见 [消息模型](/sdk/messages)。

## 错误处理

Rust 侧的错误收敛到**一个 `#[non_exhaustive]` 枚举 `BrainaryError`**(带 **7 个变体** + 构建期领域错误,并非一个不可细分的 opaque error;详见 [错误处理](/sdk/errors)),从**两个位置**冒出:构建期(`build()` / `connect()` 返回 `Err`)与运行期(消息流的某一项是 `Err`)。错误**不是**一种停机原因,而是走流的 `Err` 通道:

```rust
use brainary_agent_sdk::{query, BrainaryError, Message, ModelSelection, Options};
use futures::StreamExt;

// 构建期:配置非法(如缺 model)在此当场返回 Err,不会拖到运行期
let options = match Options::builder().model(ModelSelection::from_env()?).build() {
    Ok(o) => o,
    Err(e) => {
        eprintln!("配置错误:{e}");   // e: BrainaryError
        return Ok(());
    }
};

// 运行期:错误作为流的一项 Err 冒出,冒出后流即结束
let mut stream = query("介绍一下你自己。", options).await?;
while let Some(item) = stream.next().await {
    match item {
        Ok(Message::Result(r)) => println!("正常停机:{:?}", r.stop_reason),
        Ok(_msg) => { /* 其余消息 */ }
        Err(e) => {
            eprintln!("运行出错:{e}");
            if let Some(llmy_err) = e.as_llmy() {   // 区分底层 llmy 错误与领域错误
                eprintln!("(底层 llmy)  {llmy_err}");
            }
            break;   // 流已结束,跳出
        }
    }
}
```

**这段演示**:构建期 vs 运行期两个错误位置、流的 `Err` 通道、`as_llmy()` 区分底层与领域错误。完整变体清单见 [错误处理](/sdk/errors) 与 类型与错误参考。

## 流式多轮(用 BrainaryClient)

要接续上下文就换 `BrainaryClient`:一次 `connect` 长期持有同一 agent,逐轮 `query`,上下文自动累积(进程内原生 resume)。**每轮的流借用 `&mut client`,跑完要及时释放**,故用 `{ … }` 把每轮圈成小作用域:

```rust
use brainary_agent_sdk::{BrainaryClient, Message, ModelSelection, Options};
use futures::StreamExt;

let options = Options::builder()
    .model(ModelSelection::from_env()?)
    .enable_memory(true)
    .build()?;
let mut client = BrainaryClient::connect(options).await?;

// 第一轮
{
    let mut stream = client.query("东京今天天气怎么样?");
    while let Some(item) = stream.next().await {
        if let Message::Assistant(a) = item? {
            println!("轮1 assistant: {a:?}");
        }
    }
}   // ← 流离开作用域,归还对 client 的 &mut 借用

// 第二轮:无需重传上文,client 自己记得
{
    let mut stream = client.query("那把它记进记忆里。");
    while let Some(item) = stream.next().await { let _ = item?; }
}
```

**这段演示**:`BrainaryClient` 的多轮上下文累积、流借用 `&mut self` 的作用域纪律。中断、只读检视、手动单步见 [两个入口 · BrainaryClient](/sdk/query-and-client#brainaryclient-有状态多轮) 与 [中断与护栏](/sdk/interrupt-and-guardrails)。

## 配合自定义工具(用 BrainaryClient)

把自己写的工具挂进 agent:一个 `#[tool]` = 一个工具,`FunctionTools::new(...)` 把一组打包成命名能力单元,经 `Options` 挂载,再由 `BrainaryClient` 驱动。

> 写 `#[tool]` 的 crate 须**直接依赖 `llmy`**(宏按 crate 名解析路径)与 `schemars`/`serde`——这是复用 llmy 工具宏的固有约束,详见 [自定义工具](/sdk/tools#⚠️-依赖约束-写-tool-的-crate-必须直接依赖-llmy)。

```rust
use brainary_agent_sdk::{BrainaryClient, FunctionTools, Message, ModelSelection, Options};
use brainary_agent_sdk::tool;               // #[tool] 宏经 SDK re-export
use futures::StreamExt;
use llmy::LLMYError;
use schemars::JsonSchema;
use serde::Deserialize;

/// 工具参数:字段文档注释会进入模型看到的 JSON Schema
#[derive(Debug, Deserialize, JsonSchema)]
struct CalcArgs {
    /// 要计算的算式,例如 "123 * 456"
    expression: String,
}

#[derive(Clone, Debug)]
#[tool(
    arguments = CalcArgs,
    invoke = run,
    name = "calculate",
    description = "计算一个算术表达式"
)]
struct Calculate;

impl Calculate {
    async fn run(&self, args: CalcArgs) -> Result<String, LLMYError> {
        // 真实实现里在这里求值;示例直接回显收到的算式
        Ok(format!("已收到算式:{}", args.expression))
    }
}

// 一组工具 = 一个命名能力单元;命名空间即系统提示里的 "utils"
let utils = FunctionTools::new("utils", "小工具集").add(Calculate);

let options = Options::builder()
    .model(ModelSelection::from_env()?)
    .extra_tools(utils)               // 挂进配置(可多次调用,累积多个单元)
    .build()?;                        // 工具重名/命名空间撞名会在此当场报错

let mut client = BrainaryClient::connect(options).await?;
{
    let mut stream = client.query("帮我算一下 123 * 456");
    while let Some(item) = stream.next().await {
        if let Message::Assistant(a) = item? {
            println!("assistant: {a:?}");
        }
    }
}
```

**这段演示**:`#[tool]` 写工具、`FunctionTools` 打包命名单元、`extra_tools` 挂载、构建期校验。工具的完整签名、依赖约束与 MCP 另一类来源见 [自定义工具 FunctionTools](/sdk/tools)。

## 相关

- [能力总览](/sdk/overview) · [接口索引](/sdk/api-index)
- [两个入口](/sdk/query-and-client) · [消息模型](/sdk/messages) · [内置工具目录](/sdk/builtin-tools) · [自定义工具](/sdk/tools) · [错误处理](/sdk/errors)
- 对照 Python 版:[示例用法](/sdk-py/examples)
