---
outline: 2
---

# 示例用法（Python）

> **读完本页你能**：照抄四段**完整**程序,分别覆盖一次性任务、错误处理、有状态多轮、以及配合自定义工具。

::: warning 规划：Python 接口面(镜像 Rust)
下方代码为设计形态、尚未实现,见 [总览](/sdk-py/overview) 的规划横幅。Rust 侧对应页见 [Rust：示例用法](/sdk/examples)。
:::

这四段是把前面各页的概念**拼成整段程序**的样板。每段都写在异步上下文里(用 `asyncio.run(main())` 驱动),概念细节在每段末尾给出去处。

## 基础文件操作:内置工具(用 query)

开箱启用内置工具套件,给一个文件任务,让 agent **自行调用**内置文件工具(`read_file` / `write_file` …)。要点先说清:内置工具是**模型在 agent 循环里调用**的,你不直接调它们——你的动作是「**启用 + 授权 + 给会触发它们的 prompt**」这三件事。文件这一组底层由 `FolderPrimitive` 提供(🟠);完整目录与 schema 见 [内置工具目录](/sdk-py/builtin-tools),工具也可来自自定义 [`@tool`](/sdk-py/tools) 或 MCP。

```python
import asyncio
from brainary_agent_sdk import query, Options, AssistantMessage, ResultMessage, TextBlock

async def main():
    # 启用内置工具套件:read_file / write_file / edit_file / find_file / grep …
    # 一键装上后,模型在 agent 循环里【自行调用】它们(你不直接调)。
    options = Options(
        model=Options.model_from_env(),
        enable_default_tools=True,                    # 工具预设;文件工具由 FolderPrimitive 提供(🟠)
        allowed_tools=["read_file", "write_file"],    # 这两个免确认放行;其余落到 permission_mode / can_use_tool
    )

    # 给一个会触发文件工具的任务:调不调、怎么调由模型决定
    prompt = "读取 ./notes.md,把要点浓缩成三行,写回 ./summary.md。"
    async for msg in query(prompt=prompt, options=options):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):   # v1 只回填 Text 块
                    print(block.text)
        elif isinstance(msg, ResultMessage):
            print("停机原因:", msg.stop_reason)
    # 注:模型实际发起的 ToolUseBlock / ToolResultBlock 类型已就位、暂不透出(🟠),
    # 故这里读到的是最终文本结论;逐次工具调用的观察待 M5。

asyncio.run(main())
```

**这段演示**:开箱启用内置工具、`allowed_tools` 授权、以及 agent 自行调用文件工具的 `async for` + `isinstance` 消费。工具的授权与命令沙箱见 [权限模型](/sdk-py/permissions);目录与逐工具 schema 见 [内置工具目录](/sdk-py/builtin-tools);消息块的 v1 填充度见 [消息模型](/sdk-py/messages)。

## 错误处理

`BrainaryError` 是**异常类树的基类**(`BuildError` / `RateLimitError` / `ToolExecutionError` … 都派生自它,`except 具体子类` 可按恢复策略分支;详见 [错误处理](/sdk-py/errors))。异常从**两个位置**冒出:构建期(构造 `Options` / `BrainaryClient` / 首次装配 agent 时抛)与运行期(`async for` 消费时抛)。错误**不是**一种停机原因,而是抛异常——下面用基类 `except BrainaryError` 一网打尽,需要细分时把它换成具体子类:

```python
import asyncio
from brainary_agent_sdk import query, Options, ResultMessage, BrainaryError

async def main():
    # 构建期:配置非法(如缺 model)在此当场抛,不会拖到运行期
    try:
        options = Options(model=Options.model_from_env())
    except BrainaryError as e:
        print("配置错误:", e)
        return

    # 运行期:某步失败时 async for 抛 BrainaryError,抛出后流即结束
    try:
        async for msg in query(prompt="介绍一下你自己。", options=options):
            if isinstance(msg, ResultMessage):
                print("正常停机:", msg.stop_reason)
    except BrainaryError as e:
        print("运行出错:", e)

asyncio.run(main())
```

**这段演示**:构建期 vs 运行期两个错误位置、`async for` 抛异常、异常与 `stop_reason` 正交。完整变体清单见 [错误处理](/sdk-py/errors) 与 类型与错误参考。

## 流式多轮(用 BrainaryClient)

要接续上下文就换 `BrainaryClient`:用 `async with` 管理生命周期,`query()` 送入一轮、`receive_response()` 收这一轮回复,上下文自动累积(进程内 resume):

```python
import asyncio
from brainary_agent_sdk import BrainaryClient, Options, AssistantMessage, TextBlock

async def main():
    options = Options(model=Options.model_from_env(), enable_memory=True)

    async with BrainaryClient(options) as client:   # 建立并持有 agent(含 MCP 等活资源)
        # 第一轮
        await client.query("东京今天天气怎么样?")
        async for msg in client.receive_response():
            if isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if isinstance(block, TextBlock):
                        print("轮1:", block.text)

        # 第二轮:无需重传上文,client 自己记得
        await client.query("那把它记进记忆里。")
        async for _ in client.receive_response():
            pass
    # 退出 async with 时释放 agent

asyncio.run(main())
```

**这段演示**:`BrainaryClient` 的多轮上下文累积、`async with` 生命周期、送入一轮/收一轮。中断、只读检视、手动单步见 [两个入口 · BrainaryClient](/sdk-py/query-and-client#brainaryclient-有状态多轮)。

## 配合自定义工具(用 BrainaryClient)

把自己写的工具挂进 agent:`@tool` 标一个函数 = 一个工具,`create_sdk_mcp_server(...)` 把一组打包成命名能力单元,经 `Options.extra_tools` 挂载,再由 `BrainaryClient` 驱动:

```python
import asyncio
from brainary_agent_sdk import (
    BrainaryClient,
    Options,
    tool,
    create_sdk_mcp_server,
    AssistantMessage,
    TextBlock,
)

# 用 @tool 定义工具:收 args: dict,返回 {"content": [...]}
@tool("calculate", "计算一个算术表达式", {"expression": str})
async def calculate(args: dict) -> dict:
    expr = args["expression"]
    # 真实实现里在这里求值;示例直接回显收到的算式
    return {"content": [{"type": "text", "text": f"已收到算式:{expr}"}]}

async def main():
    # 一组工具 = 一个命名能力单元;name 即系统提示里的命名空间
    utils = create_sdk_mcp_server(name="utils", version="1.0.0", tools=[calculate])

    options = Options(
        model=Options.model_from_env(),
        extra_tools=[utils],          # 挂进配置(可给多个单元);撞名在装配时当场报错
    )

    async with BrainaryClient(options) as client:
        await client.query("帮我算一下 123 * 456")
        async for msg in client.receive_response():
            if isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if isinstance(block, TextBlock):
                        print("计算:", block.text)

asyncio.run(main())
```

**这段演示**:`@tool` 写工具、`create_sdk_mcp_server()` 打包命名单元、`extra_tools` 挂载、构建期校验。完整签名、MCP 另一类来源见 [自定义工具](/sdk-py/tools)。

## 相关

- [能力总览](/sdk-py/overview) · [接口索引](/sdk-py/api-index)
- [两个入口](/sdk-py/query-and-client) · [消息模型](/sdk-py/messages) · [内置工具目录](/sdk-py/builtin-tools) · [自定义工具](/sdk-py/tools) · [错误处理](/sdk-py/errors)
- 对照 Rust 版:[示例用法](/sdk/examples)
