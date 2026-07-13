---
outline: 2
---

# 两个入口：query() 与 BrainaryClient（Python）

> **读完本页你能**：分清一次性 `query()` 与有状态 `BrainaryClient` 的语义，会用 `async for` 消费消息流、用 `async with` 管理 client 生命周期，并知道中断与只读检视方法怎么用。

::: warning 规划：Python 接口面（镜像 Rust）
下方签名为设计形态、尚未实现，见 [总览](/sdk-py/overview) 的规划横幅。Rust 侧已实现的等价物见 [Rust：两个入口](/sdk/query-and-client)。
:::

SDK 只有两个入口，共用同一套 [Options](/sdk-py/options) 和同一条异步 [Message 流](/sdk-py/messages)。区别只有一句话：**agent 归谁持有、上下文是否跨调用累积。**

## 该用哪个？

| 你的场景 | 选 | 为什么 |
| --- | --- | --- |
| 问一次就完事 | `query()` | 每次新建 agent，跑完即弃 |
| 多轮对话，接续上下文 | `BrainaryClient` | 长期持有同一 agent，上下文自动累积（进程内 resume） |

## query()：一次性

`query()` **直接返回一个异步迭代器**，用 `async for` 消费（`async for message in query(...)`）：

```python
from brainary_agent_sdk import query, Options, AssistantMessage, ResultMessage, TextBlock

options = Options(model=Options.model_from_env())

# query() 返回异步消息流；每次调用新建 agent（相当于「开一个新会话」）
async for msg in query(prompt="介绍一下你自己。", options=options):
    if isinstance(msg, AssistantMessage):
        for block in msg.content:
            if isinstance(block, TextBlock):
                print(block.text)
    elif isinstance(msg, ResultMessage):
        print("停机：", msg.stop_reason)
```

- **一问一答**：新建 agent，把 `prompt` 跑到停机即弃；再问一句要再调一次，且不记得上次内容。
- **签名（设计形态）**——它是异步生成器，**无需 `await`**，直接 `async for`：

```python
from typing import AsyncIterable

def query(
    *,
    prompt: str | AsyncIterable[dict],
    options: Options | None = None,
) -> AsyncIterator[Message]:
    ...
```

**参数**

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `prompt` | `str \| AsyncIterable[dict]` | 必填 | 一次性输入：字符串（🟢）或**流式输入**的异步可迭代对象（🟠，见[下文](#流式输入)） |
| `options` | `Options \| None` | `None` | 配置对象；缺省时用 `Options()`（但 `model` 必填，见 [Options](/sdk-py/options)） |

**返回**：`AsyncIterator[Message]`——异步消息流，用 `async for` 逐条消费（无需 `await`）。

## BrainaryClient：有状态多轮

用 `async with` 管理生命周期，`query()` 送入一轮、`receive_response()` 收这一轮的回复：

```python
from brainary_agent_sdk import BrainaryClient, Options

options = Options(model=Options.model_from_env(), enable_memory=True)

async with BrainaryClient(options) as client:   # 建立并持有 agent（含 MCP 等活资源）
    # 第一轮
    await client.query("查一下东京天气")
    async for _ in client.receive_response():
        pass
    # 第二轮：无需重传上文，client 自己记得（进程内 resume）
    await client.query("那把它记到记忆里")
    async for _ in client.receive_response():
        pass
# 退出 async with 时释放 agent
```

- **一次进入、长期持有**：`async with BrainaryClient(options) as client` 建好 agent 并持有其名下活资源；离开 `async with` 才释放。
- **送入一轮、收一轮**：`await client.query(prompt)` 追加一轮，`client.receive_response()` 迭代到本轮 `ResultMessage` 为止。上一轮消息与工作记忆都还在。

## 怎么中断一次运行

Python 无借用限制，中断就是 client 上的一个方法（`await client.interrupt()`）。把它放进定时器 / 信号处理 / 另一个 task，条件满足时调用：

```python
import asyncio

async with BrainaryClient(options) as client:
    async def watchdog():
        await asyncio.sleep(30)
        await client.interrupt()            # 请求步间中断

    asyncio.create_task(watchdog())
    await client.query("一个很长的任务")
    async for _ in client.receive_response():
        pass
```

`interrupt()` 只是置一个标志；驱动循环在**下一步开始前**退出，并以 `stop_reason="interrupted"` 收尾。**没有「步内取消」**——进行中的那一步会先跑完。护栏细节见 [消息模型](/sdk-py/messages#stopreason)。

> 与 Rust 版的差异：Rust 因借用冲突把中断外置成句柄 `InterruptHandle`；Python 无此约束，直接做成 `client.interrupt()` 方法，更简单。

## 流式输入（str 之外）{#流式输入}

::: warning 架构已规划、尚未实现（🟠）
字符串 `prompt` 是 🟢；把**异步可迭代对象**当 `prompt` 的**流式输入**形态已承诺、v1 未实现。
:::

除了「一次给一个字符串」，`prompt` 还可接一个 **`AsyncIterable[dict]`**——**边生成边喂**：每 `yield` 一条用户消息 dict，agent 就多收一段输入（streaming-input 模式，`query(prompt=<async iterable>)`）。适合「输入本身是流」的场景：语音转写逐句到达、上游 agent 边算边产出、人在环边打字边送。

```python
# 🟠 架构已规划未实现。承诺形态。
async def user_turns() -> AsyncIterable[dict]:
    yield {"type": "user", "content": "先看一下这个仓库结构"}
    async for line in transcribe_microphone():        # 输入本身是一条流
        yield {"type": "user", "content": line}

# query() 与 BrainaryClient.query() 都接受它，返回值仍是同一条 Message 输出流
async for msg in query(prompt=user_turns(), options=options):
    ...
```

每个 yield 项是一条用户消息 dict（`{"type": "user", "content": str | list[ContentBlock]}`）。与字符串输入的唯一区别是**输入端也成了流**；输出端消费方式不变。

## BrainaryClient 完整方法面（签名）

`BrainaryClient` 的构造、生命周期与全部方法签名（设计形态，🟠）——一处看全：

```python
from typing import AsyncIterator

class BrainaryClient:
    def __init__(self, options: Options) -> None: ...
    async def __aenter__(self) -> "BrainaryClient": ...    # async with 进入：建立并持有 agent
    async def __aexit__(self, *exc) -> None: ...           # 退出：释放 agent 与活资源

    async def query(self, prompt: str | AsyncIterable[dict]) -> None: ...  # 送入一轮（str🟢 / 流式输入🟠）
    def receive_response(self) -> AsyncIterator[Message]: ...  # 迭代本轮回复直到 ResultMessage
    async def interrupt(self) -> None: ...                 # 请求步间中断

    def system_prompt(self) -> str: ...                    # 渲染后的系统提示
    def approx_context_tokens(self) -> int | None: ...     # 当前上下文近似 token 数
    def context_window(self) -> int: ...                   # 本模型上下文窗口；未注册模型为 0
    def conversation(self) -> list[TranscriptMessage]: ... # 至今的会话
    def export_transcript(self) -> SessionTranscript: ...  # 可序列化只读快照
    async def step_once(self) -> Message: ...              # 不开流地走一步（手动单步）
    async def revert(self) -> None: ...                    # 回退最近一步
```

> 会话管理相关的 `get_server_info()` / `set_model()` / `set_permission_mode()` / `rewind_files()` 见 [会话管理](/sdk-py/sessions)（🟠 跨进程面）。

**只读检视与单步**：

| 方法 | 返回 | 作用 |
| --- | --- | --- |
| `interrupt()` | `Awaitable[None]` | 请求步间中断 |
| `system_prompt()` | `str` | 渲染后的系统提示 |
| `approx_context_tokens()` | `int \| None` | 当前上下文近似 token 数 |
| `context_window()` | `int` | 本模型上下文窗口；未注册模型为 `0` |
| `conversation()` | `list[TranscriptMessage]` | 至今的会话 |
| `export_transcript()` | `SessionTranscript` | 可序列化的只读快照 |
| `step_once()` | `Awaitable[Message]` | 不开流地走一步（手动单步） |
| `revert()` | `Awaitable[None]` | 回退最近一步 |

```python
print(client.system_prompt())
print(client.approx_context_tokens(), "tokens")
transcript = client.export_transcript()     # 可 json 序列化存档
```

> `step_once()` / `revert()` / `export_transcript()` 是 Brainary 独有的能力（手动单步回退、只读快照）。

### 快照类型：SessionTranscript / TranscriptMessage {#transcript-types}

`conversation()` 与 `export_transcript()` 返回的是 SDK **自有**的只读快照类型（不复用底层 thread 结构），可 JSON 序列化存档：

```python
@dataclass
class TranscriptMessage:
    role: str                          # "system" | "user" | "assistant"
    content: list[ContentBlock]        # 该轮的内容块（见 /sdk-py/messages#content-block）

@dataclass
class SessionTranscript:
    messages: list[TranscriptMessage]  # 至今全部会话消息的只读快照
```

## 完整方法面 {#full-method-face}

方法面与状态和 [Rust 版的对照表](/sdk/query-and-client#full-method-face) 相同——`set_model` / `set_permission_mode` / `get_mcp_status` 等运行时控制均 🟠 未实现，逐项见 [边界与路线图](/sdk-py/limits)。

## 相关

- [Options 统一配置](/sdk-py/options) · [消息模型](/sdk-py/messages) · [错误处理](/sdk-py/errors)
- 进阶：[会话管理](/sdk-py/sessions) 🟠 · [权限模型](/sdk-py/permissions) 🟠
- 对照 Rust：[两个入口](/sdk/query-and-client)
