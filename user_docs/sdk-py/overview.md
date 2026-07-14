---
outline: 2
---

# brainary-agent-sdk（Python）总览

> **读完本页你能**：知道这是什么、它与 Rust 版 `brainary-agent-sdk` 的关系，看懂两个入口与状态口径，并找到本章各页入口。

## 定位

`brainary-agent-sdk`（Python）是应用开发者的高层门面：一个 `query()` 跑一次性任务、一个 `BrainaryClient` 跑有状态多轮，全部行为收敛到一个 `Options` 配置对象和一条异步 `Message` 流上——你无需接触底层实现。

它的接口面按「编码智能体 agent SDK」的目标工具视角裁剪，与 Rust 版一一对应（命名两侧一致）；Python 侧的**写法**遵循 Python 惯用法，力求清晰、简单。

## 接口一览：命名与状态 {#interface-overview}

| Brainary（Python） | 状态 | 去哪页 |
| --- | --- | --- |
| `query()` | 🟠 | [两个入口](/sdk-py/query-and-client) |
| `BrainaryClient` | 🟠 | [两个入口](/sdk-py/query-and-client) |
| `Options`（dataclass） | 🟠 | [Options](/sdk-py/options) |
| `@tool` / `create_sdk_mcp_server()`（命名能力单元） | 🟠 | [自定义工具](/sdk-py/tools) |
| `Message` / `ContentBlock` | 🟠 | [消息模型](/sdk-py/messages) |
| `await client.interrupt()`（客户端方法） | 🟠 | [两个入口](/sdk-py/query-and-client) |
| 同名原生工具（read_file/write_file/…） | 🟠 | [内置工具目录](/sdk-py/builtin-tools) |
| 会话管理接口 | 🟠 | [会话管理](/sdk-py/sessions) |
| `CanUseTool` / `PermissionMode`（6 模）/ `allowed_tools` | 🟠 | [权限模型](/sdk-py/permissions) |
| `hooks`（PreToolUse 等生命周期钩子） | 🟠 | [Hooks](/sdk-py/hooks) |
| `BrainaryError` 异常类树（`BuildError` / `RateLimitError` …） | 🟠 | [错误处理](/sdk-py/errors) |
| `Options(agents=[...])`（子 agent，SDK 一等面） | 🟠 | [Options](/sdk-py/options) |

> 全表接口均为 🟠【规划中，未完成】——架构已规划、Rust 与 Python 两侧均尚未实现。Rust 侧的对应页见 [Rust brainary-agent-sdk 总览](/sdk/overview)。

## 两个入口

| 入口 | 语义 | 形态 |
| --- | --- | --- |
| `query(prompt, options)` | 一次性；每次新建 agent | 直接是异步迭代器，用 `async for` 消费 |
| `async with BrainaryClient(options) as client` 后 `client.query(prompt)` | 有状态多轮；进程内保留上下文 | client 生命周期由 `async with` 管理 |

两者共用同一套 `Options`、同一条 `Message` 流。细节见 [两个入口](/sdk-py/query-and-client)。

## 状态说明

本 SDK **全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；本章给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非可用实现。

**状态图标图例**（全站统一，权威定义见 [边界与路线图](/sdk-py/limits)）：

| 图标 | 含义 |
| --- | --- |
| 🟢 | **已完成，可用**——已实现并可正常调用 |
| 🟠 | **规划中，未完成**——纳入本站交付面；架构与签名已规划、尚未实现 |
| ⬇️ | **下沉核心层**——非本站门面职责，归 core 层 |
| ⚪ | **暂缓 / 不纳入**——仅登记（附理由），非交付接口 |

当前**全部纳入面一律为 🟠**（尚无 🟢），不再细分实现档位。

## 三行起步引子

```python
import asyncio
from brainary_agent_sdk import query, Options, AssistantMessage, TextBlock

async def main():
    # Options 是唯一配置对象（dataclass），所有行为收敛到它上面；只有 model 必填
    options = Options(model=Options.model_from_env())

    # query() 直接返回可 async for 消费的消息流；每次调用新建 agent
    async for msg in query(prompt="介绍一下你自己。", options=options):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):
                    print(block.text)

asyncio.run(main())
```

## 下一步

- [接口索引](/sdk-py/api-index) —— 按 Functions / Classes / Types 反查接口的状态与落点
- [示例用法](/sdk-py/examples) —— 四段完整程序：一次性 / 错误处理 / 流式多轮 / 配合自定义工具
- [两个入口：query 与 BrainaryClient](/sdk-py/query-and-client)
- [Options 统一配置](/sdk-py/options)
- [消息模型](/sdk-py/messages)
- [内置工具目录](/sdk-py/builtin-tools) —— SDK 开箱自带、可被模型调用的工具目录
- [自定义工具](/sdk-py/tools) · [错误处理](/sdk-py/errors)
- 进阶（架构已规划）：[会话管理](/sdk-py/sessions) 🟠 · [权限模型](/sdk-py/permissions) 🟠 · [Hooks](/sdk-py/hooks) 🟠
- [边界与路线图](/sdk-py/limits) —— 覆盖矩阵 + Rust↔Python parity
- 对照 Rust 版：[Rust brainary-agent-sdk 总览](/sdk/overview)
