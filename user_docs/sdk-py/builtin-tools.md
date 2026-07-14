---
outline: 2
---

# 内置工具目录（Python）

> **读完本页你能**：一眼看清 SDK **开箱自带**的模型可调用工具全集——每个工具的 Brainary 原生名、输入/输出 schema 与落地状态，并知道它与「写自定义工具」「底层 primitive」两条邻线的分工。

::: warning 规划：Python 接口面（镜像 Rust）
本页是 SDK 应开箱自带的内置工具目录（目标规格）。Rust 侧见 [Rust：内置工具目录](/sdk/builtin-tools)。
:::

**状态说明**：brainary-agent-sdk 当前**全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；下方给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非占位草案。（⚪ = 暂缓 / 不纳入，非交付接口。）

## 这一页在讲什么

本页是 **SDK 对模型暴露的内置工具目录**——一个 agent **零自定义代码**即可调用的那批工具。一个编码 agent SDK 是什么，很大程度上就是由**它开箱自带这份目录**来定义的：规划目标是不用你写一行工具代码，模型即可读写文件、跑命令、搜网、拉起子 agent、维护任务清单（当前均为规划形态、尚未实现）。

它和左右两条邻线的分工要分清：

| 页面 | 回答的问题 | 面向谁 |
| --- | --- | --- |
| **本页**（内置工具目录） | SDK **自带**哪些模型可调用工具？各自 schema、状态如何？ | 想知道「装上 SDK 就白得什么」的人 |
| [自定义工具](/sdk-py/tools) | 我要**自己写**一个工具，怎么写、怎么打包挂载？ | 要扩能力的工具作者 |
| primitive 目录 | 这些工具**底层**由哪些 primitive 提供、怎么沙箱化？ | 关心底层装配与实现的人 |

换句话说：**本页 = 目标能力面（catalog）**，[自定义工具](/sdk-py/tools) = 扩展机制，primitive 目录 = 底层实现束。三者对同一批能力从「有什么 / 怎么加 / 怎么实现」三个角度切。

::: tip 命名约定
本目录一律使用 **Brainary 原生名**（`read_file`、`bash`……）。原生名是模型在本 SDK 里实际看到、实际调用的工具名。
:::

## 总映射表

一行一个工具。分组见后续各 `##` 小节。

| Brainary 原生名 | 状态 | 分组 |
| --- | --- | --- |
| `read_file` | 🟠 | 文件 |
| `write_file` | 🟠 | 文件 |
| `edit_file` | 🟠 | 文件 |
| `find_file` | 🟠 | 文件 |
| `grep` | 🟠 | 文件 |
| `delete_file` | 🟠 | 文件 |
| `bash` | 🟠 | Shell/命令 |
| `bash_output` | 🟠 | Shell/命令 |
| `kill_bash` | 🟠 | Shell/命令 |
| `web_fetch` | 🟠 | Web |
| `web_search` | 🟠 | Web |
| `ask_user_question` | 🟠 | 交互 |
| `todo_write` | 🟠（被 task 系取代） | 规划/任务 |
| `task_create` | 🟠 | 规划/任务 |
| `task_update` | 🟠 | 规划/任务 |
| `task_get` | 🟠 | 规划/任务 |
| `task_list` | 🟠 | 规划/任务 |
| `agent` | 🟠 | 子 agent |
| `list_mcp_resources` | 🟠 | MCP 资源 |
| `read_mcp_resource` | 🟠 | MCP 资源 |
| `exit_plan_mode` | 🟠 | 规划模式 |
| ~~`notebook_edit`~~ | ⚪ 不纳入 | —（见[合理不纳入](#合理不纳入)） |

各组 schema 一律以 Brainary 原生名给出；Python 侧以字典入参、`{"content": [...]}` 形状输出的惯用法呈现（镜像 Rust 的 `#[tool]` + JSON Schema）。

## 文件

模型对文件系统的六件套。**这一组底层规划由 `FolderPrimitive` 装配**——把现成的文件工具锁进一个沙箱根目录，因此 `read_file` / `write_file` / `edit_file` / `find_file` / `grep` / `delete_file` **均属 🟠【规划中，未完成】**。完整 schema 另有几处**精化缺口（🟠）**待补，逐一在下方标出。

### `read_file`｜🟠（schema 精化缺口）

**用途**：读取单个文件内容（回填给模型）。

```python
# 入参
{
    "file_path": str,          # 要读取文件的绝对路径
    "offset": int | None,      # 起始行号——🟠 待补
    "limit": int | None,       # 读取行数——🟠 待补
}
# 输出（文本文件）
{
    "content": str,            # 带行号的文件内容
    "total_lines": int,        # 文件总行数
    "lines_returned": int,     # 实际返回行数
}
# 🟠 图像输出分支待补：{ "image": str(base64), "mime_type": str, "file_size": int }
```

**精化缺口（🟠）**：现有 `read_file` **缺 `offset`/`limit` 分页**、也**缺图像文件的 base64 输出分支**，两者都需补齐。

### `write_file`｜🟠

**用途**：整份写入/覆盖一个文件。

```python
{
    "file_path": str,          # 要写入文件的绝对路径
    "content": str,            # 写入的完整内容
}
# 输出
{
    "message": str,            # 成功提示
    "bytes_written": int,      # 写入字节数
    "file_path": str,          # 被写入的路径
}
```

### `edit_file`｜🟠

**用途**：对文件做精确的字符串局部替换。

```python
{
    "file_path": str,          # 要修改文件的绝对路径
    "old_string": str,         # 被替换的原文
    "new_string": str,         # 替换成的新文
    "replace_all": bool | None,# 是否替换全部匹配（默认 False）
}
# 输出
{
    "message": str,            # 确认信息
    "replacements": int,       # 实际替换次数
    "file_path": str,          # 被编辑的路径
}
```

### `find_file`｜🟠（schema 精化缺口）

**用途**：按名查找文件。

```python
{
    "pattern": str,            # 匹配文件的通配模式（目标形态）
    "path": str | None,        # 搜索目录（默认沙箱根）
}
# 输出
{
    "matches": list[str],      # 命中的文件路径
    "count": int,              # 命中数
    "search_path": str,        # 实际搜索目录
}
```

**精化缺口（🟠）**：现有 `find_file` 是**文件名匹配**，目标形态是**通配（glob）匹配**（如 `src/**/*.py`）。需把匹配语义从「按名」升级为「按 glob 模式」。

### `grep`｜🟠（schema 精化缺口）

**用途**：按正则在文件内容里搜索。

```python
{
    "pattern": str,                # 正则表达式
    "path": str | None,            # 文件或目录（默认沙箱根）
    "glob": str | None,            # 只搜匹配此 glob 的文件——🟠 待补
    "type": str | None,            # 按文件类型过滤（如 "py"）——🟠 待补
    "output_mode": str | None,     # "content" | "files_with_matches" | "count"——🟠 待补
    "-i": bool | None,             # 大小写不敏感——🟠 待补
    "-n": bool | None,             # 显示行号——🟠 待补
    "-B": int | None,              # 匹配前 N 行上下文——🟠 待补
    "-A": int | None,              # 匹配后 N 行上下文——🟠 待补
    "-C": int | None,              # 前后各 N 行上下文——🟠 待补
    "head_limit": int | None,      # 只取前 N 条——🟠 待补
    "multiline": bool | None,      # 多行模式——🟠 待补
}
# 输出（content 模式）
{
    "matches": [
        {"file": str, "line_number": int | None, "line": str,
         "before_context": list[str] | None, "after_context": list[str] | None}
    ],
    "total_matches": int,
}
# 输出（files_with_matches 模式）：{ "files": list[str], "count": int }
```

**精化缺口（🟠）**：现有 `grep` 大体只做「正则 + 路径 → 命中」，**缺 `output_mode`（内容/文件名/计数三态）、上下文行（`-A/-B/-C`）、`type`/`glob` 过滤**等旋钮。作为主力检索工具，这些是关键能力，需逐项补齐。

### `delete_file`｜🟠

**用途**：删除沙箱内的一个文件。删除也可经 `bash` 完成，但 `FolderPrimitive` 已把它作为独立工具提供。

```python
{
    "file_path": str,          # 要删除文件的路径（限沙箱根内）
}
# 输出
{
    "message": str,            # 结果提示
    "file_path": str,
}
```

## Shell/命令

后台 shell 的完整生命周期：起（`bash`）、读增量（`bash_output`）、杀（`kill_bash`）。整组 **🟠 架构已规划、未实现**。

::: warning 沙箱边界属于这一组
命令执行是最危险的一类工具。**命令沙箱 / 权限判定就属于这里**——哪些命令自动放行、哪些要问一次、哪些禁跑，交由权限层决策，并配合沙箱隔离进程。具体机制与旋钮见 [权限模型](/sdk-py/permissions)。
:::

::: tip Git 走 bash，无一等 git 工具
**没有专门的 git 工具**——版本控制（`git status` / `diff` / `commit` / `log` …）经 `bash` 执行。好处：权限层可对 git 作用域细粒度控制（如 `allowed_tools=["Bash(git status)"]` 自动放行只读命令、`disallowed_tools=["Bash(git push *)"]` 拦推送），见 [权限模型](/sdk-py/permissions)。
:::

### `bash`｜🟠

**用途**：执行一条 shell 命令，可选后台运行。

```python
{
    "command": str,                # 要执行的命令
    "timeout": int | None,         # 超时（毫秒，最大 600000）
    "description": str | None,     # 简短说明（5-10 词）
    "run_in_background": bool | None,  # 是否后台运行
}
# 输出
{
    "output": str,                 # stdout+stderr 合并
    "exitCode": int,               # 退出码
    "killed": bool | None,         # 是否因超时被杀
    "shellId": str | None,         # 后台进程的 shell id
}
```

### `bash_output`｜🟠

**用途**：读取一个后台 shell 自上次读取以来的增量输出。

```python
{
    "bash_id": str,                # 后台 shell 的 id
    "filter": str | None,          # 可选正则，过滤输出行
}
# 输出
{
    "output": str,                 # 新增输出
    "status": str,                 # "running" | "completed" | "failed"
    "exitCode": int | None,        # 完成时的退出码
}
```

### `kill_bash`｜🟠

**用途**：杀掉一个后台 shell。

```python
{
    "shell_id": str,               # 要杀掉的后台 shell id
}
# 输出
{
    "message": str,
    "shell_id": str,
}
```

## Web

出网两件套：抓取单页与联网搜索。整组 **🟠**。

### `web_fetch`｜🟠

**用途**：抓取一个 URL，用 `prompt` 对其内容做提炼后回填。

```python
{
    "url": str,                    # 要抓取的 URL
    "prompt": str,                 # 对抓到内容运行的提示
}
# 输出
{
    "bytes": int,                  # 抓取内容字节数
    "code": int,                   # HTTP 状态码
    "codeText": str,               # HTTP 状态文本
    "result": str,                 # prompt 应用于内容后的结果
    "durationMs": int,             # 抓取+处理耗时
    "url": str,                    # 实际抓取的 URL
}
```

### `web_search`｜🟠

**用途**：联网搜索，可按域名白/黑名单过滤。

```python
{
    "query": str,                          # 搜索词
    "allowed_domains": list[str] | None,   # 仅保留这些域名的结果
    "blocked_domains": list[str] | None,   # 永不包含这些域名的结果
}
# 输出
{
    "query": str,
    "results": list[str | {"tool_use_id": str, "content": list[{"title": str, "url": str}]}],
    "durationSeconds": float,
}
```

## 交互

human-in-the-loop 的澄清工具，让 agent 在执行中反问用户。**🟠**。

### `ask_user_question`｜🟠

**用途**：执行中向用户抛出 1-4 个带选项的澄清问题；答案由权限系统回填。

```python
{
    "questions": [                 # 1-4 个问题
        {
            "question": str,       # 完整问题
            "header": str,         # 极短标签（≤12 字符）
            "options": [           # 2-4 个选项
                {"label": str,     # 选项显示文本（1-5 词）
                 "description": str}  # 该选项含义说明
            ],
            "multiSelect": bool,   # 是否允许多选
        }
    ],
}
# 输出
{
    "questions": [ ... ],          # 回显所问的问题
    "answers": dict[str, str],     # 问题文本 → 答案；多选以逗号连接
}
```

这条工具与 [权限模型](/sdk-py/permissions) 的审批/输入回填链路强相关。

## 规划/任务

让模型自己维护一份任务清单。历史上是单一的 `todo_write`，**现已被 `task_*` 四件套取代**（更结构化、可依赖、可指派）。整组 **🟠**。

### `todo_write`｜🟠（被 task 系取代）

**用途**：整份覆写一份 todo 清单。**已被 `task_*` 取代**，仅为兼容登记。

```python
{
    "todos": [
        {"content": str,           # 任务描述
         "status": str,            # "pending" | "in_progress" | "completed"
         "activeForm": str}        # 进行时描述
    ]
}
# 输出：{ "message": str, "stats": {"total": int, "pending": int, "in_progress": int, "completed": int} }
```

### `task_create`｜🟠

**用途**：新建一个任务，返回分配到的 id。

```python
{
    "subject": str,                # 简短标题
    "description": str,            # 详细正文
    "activeForm": str | None,      # 进行时标签
    "metadata": dict | None,       # 任意调用方元数据
}
# 输出：{ "task": {"id": str, "subject": str} }
```

### `task_update`｜🟠

**用途**：按 id 局部修改任务（状态、依赖、指派……）。

```python
{
    "taskId": str,
    "status": "pending" | "in_progress" | "completed" | "deleted" | None,
    "subject": str | None,
    "description": str | None,
    "activeForm": str | None,
    "addBlocks": list[str] | None,     # 本任务新阻塞的任务 id
    "addBlockedBy": list[str] | None,  # 新阻塞本任务的任务 id
    "owner": str | None,
    "metadata": dict | None,
}
# 输出：{ "success": bool, "taskId": str, "updatedFields": list[str], "error": str | None, "statusChange": {...} | None }
```

### `task_get`｜🟠

**用途**：按 id 读取单个任务全貌。

```python
{
    "taskId": str,
}
# 输出：{ "task": {"id", "subject", "description", "status", "blocks", "blockedBy"} | None }
```

### `task_list`｜🟠

**用途**：列出全部任务的摘要视图。

```python
{}   # 无入参
# 输出：{ "tasks": [ {"id", "subject", "status", "owner": str | None, "blockedBy": list[str]} ] }
```

## 子 agent

模型可**调用**的子 agent 生成工具——让主 agent 把一段自包含子任务派给一个专门子 agent 跑完再收敛结果。**🟠**。

::: warning 与配置类型 `AgentDefinition` 区分
本页的 `agent` 是**模型可调用的运行时工具**（模型主动拉起子 agent）。它与**配置态的子 agent 定义** `AgentDefinition`（在 [Options/agents](/sdk-py/options) 里声明可用的子 agent 类型）是两回事：后者是「有哪些子 agent 可选」，前者是「模型现在就调起其中一个」。
:::

### `agent`｜🟠

**用途**：拉起一个指定类型的子 agent 执行子任务。

```python
{
    "description": str,            # 任务的极短描述（3-5 词）
    "prompt": str,                 # 交给子 agent 执行的具体任务
    "subagent_type": str,          # 使用的专门子 agent 类型（对应某个 AgentDefinition）
}
# 输出
{
    "result": str,                 # 子 agent 的最终结果
    "usage": dict | None,          # token 用量
    "total_cost_usd": float | None,# 估算总成本
    "duration_ms": int | None,     # 执行耗时
}
```

## MCP 资源

对已挂载 MCP server 暴露的**资源**（非工具）做发现与读取。**🟠**。MCP 工具本身的挂载见 [自定义工具 · MCP](/sdk-py/tools)。

### `list_mcp_resources`｜🟠

**用途**：列出（可按 server 过滤）可用的 MCP 资源。

```python
{
    "server": str | None,          # 可选：按 server 名过滤
}
# 输出
{
    "resources": [
        {"uri": str, "name": str, "description": str | None,
         "mimeType": str | None, "server": str}
    ],
    "total": int,
}
```

### `read_mcp_resource`｜🟠

**用途**：按 server + uri 读取一个 MCP 资源的内容。

```python
{
    "server": str,                 # MCP server 名
    "uri": str,                    # 要读取的资源 URI
}
# 输出
{
    "contents": [
        {"uri": str, "mimeType": str | None, "text": str | None, "blob": str | None}
    ],
    "server": str,
}
```

## 规划模式

配合权限的 **plan 模式**：agent 先只读地做出方案，经用户批准后再退出计划模式动手执行。**🟠**。

### `exit_plan_mode`｜🟠

**用途**：提交一份方案供用户批准，批准后退出 plan 模式。

```python
{
    "plan": str,                   # 交给用户审批的方案
}
# 输出
{
    "message": str,
    "approved": bool | None,       # 用户是否批准
}
```

plan 模式作为一种权限模式，其判定与「只读探索 → 批准 → 执行」的流转见 [权限模型](/sdk-py/permissions)。

## 合理不纳入

- **`notebook_edit`｜⚪ 不纳入**：Jupyter notebook 单元格编辑是 **Jupyter 专属、场景 niche** 的能力，不属于通用 agent SDK 的核心内置面。需要时可作为一个自定义工具或 MCP 能力按需接入，而非默认目录成员。

## 相关

- [自定义工具](/sdk-py/tools) —— 怎么**写**并挂载自己的工具（`@tool` / `create_sdk_mcp_server` / MCP）
- [Options 配置](/sdk-py/options) —— 子 agent 定义 `AgentDefinition`、工具装配旋钮
- [权限模型](/sdk-py/permissions) —— 命令沙箱、plan 模式、审批与输入回填
- [消息模型](/sdk-py/messages) —— 工具调用/结果在消息流里的呈现
- [Rust：内置工具目录](/sdk/builtin-tools) —— 本页的 Rust 对应
