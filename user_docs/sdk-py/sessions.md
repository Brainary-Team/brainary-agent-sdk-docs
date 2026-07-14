---
outline: 2
---

# 会话管理（Python，架构已规划）

> **读完本页你能**：分清「进程内 resume / transcript 导出 / 跨进程 session 管理」三件事，拿到 Python 形态**已定形**的会话管理函数（函数名、参数、返回结构都已承诺，与 [Rust 侧](/sdk/sessions) 逐参数对齐），并看懂 resume 家族、运行时控制与文件检查点的规划落点。

::: warning 架构已规划、尚未实现（🟠）
本页的**函数签名与字段集已经定形并承诺**，不再是「待对齐后定稿」的草稿：函数名、参数、`SessionInfo` 字段在 Python 与 Rust 两侧**逐参数对齐**、就此固定。仍标 🟠，是因为它们**当前未实现**——差的是底层那层**跨进程持久化存储**（会话落盘、编号、索引），这一块由底层拥有。你现在能用的会话能力只有：进程内多轮 resume（[BrainaryClient](/sdk-py/query-and-client)）与只读快照导出（`export_transcript()`）。
:::

## 三件事，别混淆

| 能力 | 是什么 | 状态 | 在哪 |
| --- | --- | --- | --- |
| **进程内 resume** | 同一个 client 活着期间多轮上下文自动累积 | 🟠 | [两个入口](/sdk-py/query-and-client) |
| **transcript 导出** | 把当前会话导成可序列化只读快照（**只导出、不可续跑**） | 🟠 | `client.export_transcript()` |
| **跨进程 session 管理** | 把多份历史会话持久化、list / 查看 / 重命名 / 打标签 / 载回续跑 | 🟠 未实现 | 本页 |

> **session 管理 ≠ resume**，是两件事——只是都压在「跨进程持久化」这一未做的底座上。

## 定形的会话函数

Brainary 提供一组 module 级会话管理函数，统一做成 **async 函数、关键字参数**（与 `query()` / `BrainaryClient` 的异步风格一致）：

| 函数 | 作用 | 状态 |
| --- | --- | --- |
| `list_sessions(...)` | 列出历史会话（可按目录过滤、分页） | 🟠 |
| `get_session_messages(session_id, ...)` | 读某会话的消息（可分页） | 🟠 |
| `get_session_info(session_id, ...)` | 读某会话的元信息（`SessionInfo`） | 🟠 |
| `rename_session(session_id, title, ...)` | 重命名会话（设自定义标题） | 🟠 |
| `tag_session(session_id, tag, ...)` | 给会话打标签（`None` 清除） | 🟠 |

> 这些是 **module 级 async 函数**，形态就此固定。仍在底层拥有、尚未落地的，只有它们背后那层**跨进程持久化存储**——把多份会话落盘、编号、按目录索引。函数面不随实现变动。

## 会话函数签名（已承诺）

以下签名**已定形**，与 [Rust 侧](/sdk/sessions) 逐参数对齐。均为 async、关键字参数：

### 返回类型 `SessionInfo`（完整字段集）

`SessionInfo` 是一份历史会话的元信息（dataclass、可序列化）。字段集**已恢复完整**——这些字段正是让「列一屏历史会话」在编码工作流里真正有用的东西：

```python
from dataclasses import dataclass

@dataclass
class SessionInfo:
    session_id: str
    summary: str | None
    created_at: int | None
    last_modified: int
    num_turns: int
    cwd: str | None
    git_branch: str | None
    file_size: int | None
    first_prompt: str | None
    custom_title: str | None
    tag: str | None
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `session_id` | `str` | 会话唯一标识，是整套会话 API 的 join key（见下「先决条件」） |
| `summary` | `str \| None` | 展示标题：自定义标题 → 自动摘要 → 首条提示，逐级回退 |
| `created_at` | `int \| None` | 创建时间（毫秒时间戳） |
| `last_modified` | `int` | 最后修改时间（毫秒时间戳）；列表按它降序排 |
| `num_turns` | `int` | 会话累计轮数 |
| `cwd` | `str \| None` | 会话的工作目录 |
| `git_branch` | `str \| None` | 会话结束时所在的 git 分支 |
| `file_size` | `int \| None` | 会话文件字节数（远端存储后端为 `None`） |
| `first_prompt` | `str \| None` | 会话里第一条有意义的用户提示 |
| `custom_title` | `str \| None` | 用户设置的会话标题（`rename_session` 写入） |
| `tag` | `str \| None` | 用户设置的标签（`tag_session` 写入） |

> **为什么字段要这么全？** `git_branch` / `cwd` / `last_modified` 是让列表**在编码工作流里可用**的关键：一屏历史会话，靠「哪个分支、哪个目录、最近何时动过」才能快速认出「就是上周那个重构 auth 的会话」，而不是对着一串 UUID 干瞪眼。

### `list_sessions()`

```python
async def list_sessions(
    *,
    directory: str | None = None,
    limit: int | None = None,
    offset: int = 0,
) -> list[SessionInfo]:
    ...
```

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `directory` | `str \| None` | `None` | 列举哪个项目目录的会话；省略则跨全部项目 |
| `limit` | `int \| None` | `None` | 最多返回多少条 |
| `offset` | `int` | `0` | 从头跳过多少条（配合 `limit` 分页） |

**返回**：`list[SessionInfo]`，按 `last_modified` 降序（最新在前）。

### `get_session_messages()`

```python
async def get_session_messages(
    session_id: str,
    *,
    directory: str | None = None,
    limit: int | None = None,
    offset: int = 0,
) -> list[TranscriptMessage]:
    ...
```

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `session_id` | `str` | 必填 | 要取消息的会话 ID |
| `directory` | `str \| None` | `None` | 在哪个项目目录查找；省略则跨全部项目 |
| `limit` | `int \| None` | `None` | 最多返回多少条消息 |
| `offset` | `int` | `0` | 从头跳过多少条 |

**返回**：`list[TranscriptMessage]`（复用 transcript 的 SDK 自有类型）。

### `get_session_info()`

```python
async def get_session_info(
    session_id: str,
    *,
    directory: str | None = None,
) -> SessionInfo | None:
    ...
```

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `session_id` | `str` | 必填 | 要查询的会话 ID |
| `directory` | `str \| None` | `None` | 项目目录；省略则跨全部项目查找 |

**返回**：`SessionInfo | None`——未找到则为 `None`。

### `rename_session()`

```python
async def rename_session(
    session_id: str,
    title: str,
    *,
    directory: str | None = None,
) -> None:
    ...
```

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `session_id` | `str` | 必填 | 要重命名的会话 ID |
| `title` | `str` | 必填 | 新标题；去空白后不可为空 |
| `directory` | `str \| None` | `None` | 项目目录；省略则跨全部项目查找 |

**返回**：`None`。写入后新标题出现在后续读取的 `SessionInfo.custom_title`。

### `tag_session()`

```python
async def tag_session(
    session_id: str,
    tag: str | None,
    *,
    directory: str | None = None,
) -> None:
    ...
```

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `session_id` | `str` | 必填 | 要打标签的会话 ID |
| `tag` | `str \| None` | 必填 | 标签字符串；`None` 清除标签 |
| `directory` | `str \| None` | `None` | 项目目录；省略则跨全部项目查找 |

**返回**：`None`。之后可在 `list_sessions()` 结果里按 `SessionInfo.tag` 过滤。

> 这些函数统一为 **async**，以贴合其余入口的异步风格；worktree 展开开关（`include_worktrees`）暂不进面，留待底层决定默认行为。

## 先决条件：session id 访问器

整套会话 API 的 join key 是 `session_id`——`get_session_messages` / `get_session_info` / `rename_session` / `tag_session` 第一个参数都是它。而 **Brainary 当前的 `BrainaryClient` 还没有暴露「当前会话 id」的访问器**：进程内 resume 不需要 id，所以从没做过。

因此 **`get_server_info`（返回 session id + 能力信息）是这一整套会话 API 的先决条件**——它是把「活着的进程内会话」和「磁盘上的历史会话」对上号的那把钥匙。没有 session id 访问器，就无法在运行结束后用同一个 id 去 list / rename / resume。签名（🟠 承诺形态）：

```python
class BrainaryClient:
    async def get_server_info(self) -> dict | None: ...
    # 返回 {"session_id": str, ...能力信息}；无活动会话时为 None
```

```python
# ⚠️ 规划（🟠）：get_server_info 返回 session id + 能力信息。
async with BrainaryClient(options) as client:
    info = await client.get_server_info()   # -> dict | None
    session_id = info["session_id"]         # ← 整套会话 API 的 join key
```

## resume 家族：三种续跑

会话管理的另一半是「载回续跑」。Brainary 规划三个 resume 入口（前两者的**进程内**形态已 🟠，跨进程形态 🟠），作为 [Options](/sdk-py/options) 上的装配旋钮：

| 入口 | 语义 | 状态 |
| --- | --- | --- |
| `continue_conversation` | 续**最近一份**会话（不必给 id） | 🟠 跨进程 |
| `resume(session_id)` | 按 **session id** 续某份具体会话 | 🟠 进程内 resume（规划中）/ 跨进程载回（规划中） |
| `fork_session` | resume 时**分叉**到一个新 session id，原会话不动 | 🟠 |

```python
# ⚠️ 跨进程形态未实现（🟠）；进程内 resume 已 🟠（见 /sdk-py/query-and-client）。
options = Options(
    model=Options.model_from_env(),
    continue_conversation=True,   # 续最近一份历史会话
    # 或：
    resume=session_id,            # 按 id 续某份会话
    fork_session=True,            # resume 时分叉到新 session id
)
```

- **进程内 resume（规划中）**：同一个 `BrainaryClient` 活着期间多轮上下文自动累积，无需 id。
- **跨进程 resume 未实现**：把磁盘上一份历史会话载回成能继续跑的 agent，卡在下面「依赖的底座」的 transcript resume 上。
- **`fork_session`** 用于「从某历史会话分叉出一条新支线」：以它为起点续跑，但落到一个**新** session id，原会话保持只读不变。

## 运行时客户端控制

除了会话函数，`BrainaryClient` 还规划两个**运行时切换**方法（`set_model` / `set_permission_mode`），承诺形态、未实现（🟠）：

```python
class BrainaryClient:
    async def set_model(self, model: str | None = None) -> None: ...        # None 重置为默认
    async def set_permission_mode(self, mode: PermissionMode) -> None: ...  # 见 /sdk-py/permissions
```

```python
# ⚠️ 未实现（🟠）；当前需重建 client 才能换模型 / 权限模式。
async with BrainaryClient(options) as client:
    await client.set_model("...")               # 运行时切换模型；None 重置为默认
    await client.set_permission_mode("plan")    # 运行时切换权限模式
```

- `set_model(model)`：当前模型在 `Options` 装配时固定，运行时切换需重建 client；此方法把「不重建 client 就换模型」提上路线图。传 `None` 重置为默认。
- `set_permission_mode(mode)`：整套权限模式（`plan` / `acceptEdits` / …）本身也尚未落地，语义与取值见 [权限模型](/sdk-py/permissions)。

## 文件检查点 rewind_files

`rewind_files` 是**文件级**检查点/恢复：把工作区文件恢复到「某条用户消息当时」的状态。它与 `revert()` 是**两码事**，别混：

| 能力 | 粒度 | 恢复什么 | 状态 |
| --- | --- | --- | --- |
| `revert()` | **步级** | 撤掉最近一步对话（会话状态回退一步） | 🟠 规划中 |
| `rewind_files(message_id)` | **文件级** | 把磁盘上的文件回滚到某条用户消息时的快照 | 🟠 未实现 |

```python
class BrainaryClient:
    async def rewind_files(self, message_id: str) -> None: ...  # 恢复到该用户消息当时的文件快照
```

```python
# ⚠️ 未实现（🟠）；需要一层文件检查点开关（enable_file_checkpointing）。
async with BrainaryClient(options) as client:
    await client.rewind_files(user_message_id)   # 把文件恢复到该用户消息当时的状态
```

对一个**编码 agent** 而言，这是 **ADAPT-CORE**（值得下沉到 core 层实现）：agent 改坏了一批文件、想整体退回到某一轮之前——这正是编码工作流的核心撤销语义，比步级 `revert()` 更贴近「我要回到改动之前的磁盘状态」。它依赖一层文件检查点存储（`enable_file_checkpointing`），逐项决策见 [边界与路线图](/sdk-py/limits)。

## 依赖的底座

要实现上面这些，需要先有一层未做的**跨进程持久化**底座，它本身又分两块（对应上面「三件事」里未做的第三件）：

1. **session 索引**：把多份会话落盘、编号、按目录索引，可列举 / 查元信息 / 重命名 / 打标签——即本页 `list_sessions` / `get_session_info` / `rename_session` / `tag_session` 背后的存储层，归底层拥有。
2. **transcript resume**：把导出的 transcript **载回**一个能继续跑的 agent——目前没有「用历史重建 agent」的构造器，故无法续跑。

两块都归入路线图，逐项决策见 [边界与路线图](/sdk-py/limits) 的覆盖矩阵。

## 相关

- [两个入口：BrainaryClient](/sdk-py/query-and-client) —— 进程内 resume（🟠）、`get_server_info` 与运行时控制
- [权限模型](/sdk-py/permissions) 🟠 · [边界与路线图](/sdk-py/limits)
- 对照 Rust：[会话管理](/sdk/sessions)
