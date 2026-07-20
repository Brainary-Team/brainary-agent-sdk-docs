---
outline: 2
---

# brainary-agent-sdk（Python）· 规划中的接口清单

## 一、函数

### 入口

| 函数 | 干什么 |
| --- | --- |
| `query(prompt, options)` | 问一次就完事。每次新建 agent，跑完即弃，直接 `async for` 消费消息流。 |

```python
async for msg in query(prompt="介绍一下你自己。", options=options):
    ...
```

- `prompt` 可以是字符串，也可以是一个异步流（边生成边喂，适合语音逐句、上游边算边送）。
- 不记得上一次的内容；要接续上下文请用下面的 `BrainaryClient`。

### 会话管理（读磁盘上的历史会话）

> 注意：这些是**独立函数**，不是 `BrainaryClient` 的方法。

| 函数 | 干什么 |
| --- | --- |
| `list_sessions(...)` | 列出历史会话（支持目录过滤、分页） |
| `get_session_messages(session_id, ...)` | 读某个会话的消息列表 |
| `get_session_info(session_id, ...)` | 读某个会话的元信息 |
| `rename_session(session_id, title, ...)` | 给会话改名 |
| `tag_session(session_id, tag, ...)` | ⚪ 打标签，**暂缓** |

### 定义工具

| 名称 | 干什么 |
| --- | --- |
| `@tool(name, desc, schema)` | 装饰器：把一个 async 函数变成工具 |
| `create_sdk_mcp_server(name, version, tools)` | 把一组工具打包成一个能力单元 |

**小结**：可交付函数 5 个（`query` + 4 个会话读写）；工具相关 2 个；`tag_session` 暂缓。

---

## 二、`BrainaryClient` 的方法

> 有状态的多轮客户端，长期持有同一个 agent，上下文自动累积。
> 用 `async with` 管理生命周期。

```python
async with BrainaryClient(options) as client:
    await client.query("查一下东京天气")
    async for _ in client.receive_response():
        pass
```

### 核心方法（会实现，共 8 个）

| 方法 | 干什么 |
| --- | --- |
| `query(prompt)` | 送入一轮对话 |
| `receive_response()` | 迭代读这一轮的回复，直到本轮结束 |
| `interrupt()` | 请求中途停下（下一步开始前退出，进行中的一步会先跑完） |
| `system_prompt()` | 看渲染后的系统提示 |
| `approx_context_tokens()` | 当前上下文大概占多少 token |
| `context_window()` | 本模型的上下文窗口大小（未知返回 0） |
| `conversation()` | 拿到至今的会话消息列表 |
| `export_transcript()` | 导出可存档的只读会话快照 |

外加两个手动驱动的方法（Brainary 独有）：

| 方法 | 干什么 |
| --- | --- |
| `step_once()` | 手动往前走一步（不加新的用户输入） |
| `revert()` | 撤销最近走的一步 |

生命周期由 `async with`（`__aenter__` / `__aexit__`）管理，退出时自动释放，无需手动 disconnect。

### 暂不实现的方法（登记备查）

对齐用、v1 先不做：`set_model`、`set_permission_mode`、`get_server_info`、`rewind_files`、MCP 运行时控制、后台任务等。详见 [边界与路线图](/sdk-py/limits)。

---

## 三、总量一览

| 分类 | 数量 |
| --- | --- |
| 可交付函数 | 5（`query` + 4 会话读写） |
| 工具相关 | 2（`@tool` / `create_sdk_mcp_server`） |
| 暂缓函数 | 1（`tag_session`） |
| `BrainaryClient` 核心方法 | 10（8 常用 + `step_once` / `revert`） |
| `BrainaryClient` 暂不实现的方法 | 若干（见上） |
