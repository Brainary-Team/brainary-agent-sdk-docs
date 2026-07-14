---
outline: 2
---

# 内置工具目录（Rust）

> **读完本页你能**：一眼看清 Brainary SDK **开箱自带**的模型可调用工具全集——每个工具的原生名、输入/输出 schema 与落地状态，并知道它与「写自定义工具」「底层 primitive」两条邻线的分工。

**状态说明**：brainary-agent-sdk 当前**全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；下方给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非占位草案。（⚪ = 暂缓 / 不纳入，非交付接口。）

## 这一页在讲什么

本页是 **SDK 对模型暴露的内置工具目录**——一个 agent **零自定义代码**即可调用的那批工具。一个编码智能体 SDK 的核心，很大程度上就是由**它开箱自带这份目录**来定义的：规划目标是不用你写一行工具代码，模型即可读写文件、跑命令、搜网、拉起子 agent、维护任务清单（当前均为规划形态、尚未实现）。

它和左右两条邻线的分工要分清：

| 页面 | 回答的问题 | 面向谁 |
| --- | --- | --- |
| **本页**（内置工具目录） | SDK **自带**哪些模型可调用工具？各自 schema、状态如何？ | 想知道「装上 SDK 就白得什么」的人 |
| [自定义工具](/sdk/tools) | 我要**自己写**一个工具，怎么写、怎么打包挂载？ | 要扩能力的工具作者 |
| primitive 目录 | 这些工具**底层**由哪些 primitive 提供、怎么沙箱化？ | 关心底层装配与实现的人 |

换句话说：**本页 = 目标能力面（catalog）**，[自定义工具](/sdk/tools) = 扩展机制，primitive 目录 = 底层实现束。三者对同一批能力从「有什么 / 怎么加 / 怎么实现」三个角度切。

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
| `agent`（旧名 `task`） | 🟠 | 子 agent |
| `list_mcp_resources` | 🟠 | MCP 资源 |
| `read_mcp_resource` | 🟠 | MCP 资源 |
| `exit_plan_mode` | 🟠 | 规划模式 |
| ~~`notebook_edit`~~ | ⚪ 不纳入 | —（见[合理不纳入](#合理不纳入)） |

各组 schema 一律以 Brainary 原生名给出；这里的形态是 SDK **应当**产出的目标规格，Rust 侧以 `#[tool]` + JSON Schema 惯用法呈现（`arguments` 即入参类型的 `JsonSchema` 派生，工具返回结构化输出）。

## 文件

模型对文件系统的六件套。**这一组底层规划由 `FolderPrimitive` 装配**——把 `llmy` 现成的文件工具锁进一个沙箱根目录，因此 `read_file` / `write_file` / `edit_file` / `find_file` / `grep` / `delete_file` **均属 🟠【规划中，未完成】**。完整 schema 另有几处**精化缺口（🟠）**待补，逐一在下方标出。

### `read_file`｜🟠（schema 精化缺口）

**用途**：读取单个文件内容（回填给模型）。

```rust
#[derive(Deserialize, JsonSchema)]
struct ReadFileArgs {
    /// 要读取文件的绝对路径
    file_path: String,
    /// 起始行号（从该行开始读）——🟠 待补
    offset: Option<u64>,
    /// 读取行数——🟠 待补
    limit: Option<u64>,
}

// 输出（文本文件）：带行号的内容 + 计数
struct ReadFileOutput {
    content: String,       // 带行号的文件内容
    total_lines: u64,      // 文件总行数
    lines_returned: u64,   // 实际返回行数
}
// 🟠 图像输出分支待补：{ image: String(base64), mime_type: String, file_size: u64 }
```

**精化缺口（🟠）**：现有 `read_file` **缺 `offset`/`limit` 分页**、也**缺图像文件的 base64 输出分支**，两者都需补齐。

### `write_file`｜🟠

**用途**：整份写入/覆盖一个文件。

```rust
#[derive(Deserialize, JsonSchema)]
struct WriteFileArgs {
    /// 要写入文件的绝对路径
    file_path: String,
    /// 写入的完整内容
    content: String,
}
struct WriteFileOutput {
    message: String,       // 成功提示
    bytes_written: u64,    // 写入字节数
    file_path: String,     // 被写入的路径
}
```

### `edit_file`｜🟠

**用途**：对文件做精确的字符串局部替换。

```rust
#[derive(Deserialize, JsonSchema)]
struct EditFileArgs {
    /// 要修改文件的绝对路径
    file_path: String,
    /// 被替换的原文
    old_string: String,
    /// 替换成的新文
    new_string: String,
    /// 是否替换全部匹配（默认 false）
    replace_all: Option<bool>,
}
struct EditFileOutput {
    message: String,       // 确认信息
    replacements: u64,     // 实际替换次数
    file_path: String,     // 被编辑的路径
}
```

### `find_file`｜🟠（schema 精化缺口）

**用途**：按名查找文件。

```rust
#[derive(Deserialize, JsonSchema)]
struct FindFileArgs {
    /// 匹配文件的通配模式（目标形态）
    pattern: String,
    /// 搜索目录（默认沙箱根）
    path: Option<String>,
}
struct FindFileOutput {
    matches: Vec<String>,  // 命中的文件路径
    count: u64,            // 命中数
    search_path: String,   // 实际搜索目录
}
```

**精化缺口（🟠）**：现有 `find_file` 是**文件名匹配**，目标形态是**通配（glob）匹配**（如 `src/**/*.rs`）。需把匹配语义从「按名」升级为「按 glob 模式」。

### `grep`｜🟠（schema 精化缺口）

**用途**：按正则在文件内容里搜索。

```rust
#[derive(Deserialize, JsonSchema)]
struct GrepArgs {
    /// 正则表达式
    pattern: String,
    /// 文件或目录（默认沙箱根）
    path: Option<String>,
    /// 只搜匹配此 glob 的文件——🟠 待补
    glob: Option<String>,
    /// 按文件类型过滤（如 "rust"）——🟠 待补
    r#type: Option<String>,
    /// 输出模式："content" | "files_with_matches" | "count"——🟠 待补
    output_mode: Option<String>,
    /// 大小写不敏感（-i）——🟠 待补
    case_insensitive: Option<bool>,
    /// 显示行号（-n）——🟠 待补
    line_numbers: Option<bool>,
    /// 匹配前 N 行上下文（-B）——🟠 待补
    before_context: Option<u32>,
    /// 匹配后 N 行上下文（-A）——🟠 待补
    after_context: Option<u32>,
    /// 前后各 N 行上下文（-C）——🟠 待补
    context: Option<u32>,
    /// 只取前 N 条——🟠 待补
    head_limit: Option<u32>,
    /// 多行模式——🟠 待补
    multiline: Option<bool>,
}

// 输出（content 模式）
struct GrepContentOutput {
    matches: Vec<GrepMatch>,   // 每条含 file/line_number/line/before_context/after_context
    total_matches: u64,
}
// 输出（files_with_matches 模式）：{ files: Vec<String>, count: u64 }
```

**精化缺口（🟠）**：现有 `grep` 大体只做「正则 + 路径 → 命中」，**缺 `output_mode`（内容/文件名/计数三态）、上下文行（`-A/-B/-C`）、`type`/`glob` 过滤**等旋钮。这些是作为主力检索工具的关键能力，需逐项补齐。

### `delete_file`｜🟠

**用途**：删除沙箱内的一个文件。删除也可经 `bash` 完成，但 `FolderPrimitive` 已把它作为独立工具提供。

```rust
#[derive(Deserialize, JsonSchema)]
struct DeleteFileArgs {
    /// 要删除文件的路径（限沙箱根内）
    file_path: String,
}
struct DeleteFileOutput {
    message: String,       // 结果提示
    file_path: String,
}
```

## Shell/命令

后台 shell 的完整生命周期：起（`bash`）、读增量（`bash_output`）、杀（`kill_bash`）。整组 **🟠 架构已规划、未实现**。

::: warning 沙箱边界属于这一组
命令执行是最危险的一类工具。**命令沙箱 / 权限判定就属于这里**——哪些命令自动放行、哪些要问一次、哪些禁跑，交由权限层决策，并配合沙箱隔离进程。具体机制与旋钮见 [权限模型](/sdk/permissions)。
:::

::: tip Git 走 bash，无一等 git 工具
**没有专门的 git 工具**——版本控制（`git status` / `diff` / `commit` / `log` …）经 `bash` 执行。好处：权限层可对 git 作用域细粒度控制（如 `allowed_tools=["Bash(git status)"]` 自动放行只读命令、`disallowed_tools=["Bash(git push *)"]` 拦推送），见 [权限模型](/sdk/permissions)。
:::

### `bash`｜🟠

**用途**：执行一条 shell 命令，可选后台运行。

```rust
#[derive(Deserialize, JsonSchema)]
struct BashArgs {
    /// 要执行的命令
    command: String,
    /// 超时（毫秒，最大 600000）
    timeout: Option<u64>,
    /// 简短说明（5-10 词）
    description: Option<String>,
    /// 是否后台运行
    run_in_background: Option<bool>,
}
struct BashOutput {
    output: String,          // stdout+stderr 合并
    exit_code: i32,          // 退出码
    killed: Option<bool>,    // 是否因超时被杀
    shell_id: Option<String>,// 后台进程的 shell id
}
```

### `bash_output`｜🟠

**用途**：读取一个后台 shell 自上次读取以来的增量输出。

```rust
#[derive(Deserialize, JsonSchema)]
struct BashOutputArgs {
    /// 后台 shell 的 id
    bash_id: String,
    /// 可选正则，过滤输出行
    filter: Option<String>,
}
struct BashOutputOutput {
    output: String,              // 新增输出
    status: String,              // "running" | "completed" | "failed"
    exit_code: Option<i32>,      // 完成时的退出码
}
```

### `kill_bash`｜🟠

**用途**：杀掉一个后台 shell。

```rust
#[derive(Deserialize, JsonSchema)]
struct KillBashArgs {
    /// 要杀掉的后台 shell id
    shell_id: String,
}
struct KillBashOutput {
    message: String,
    shell_id: String,
}
```

## Web

出网两件套：抓取单页与联网搜索。整组 **🟠**。

### `web_fetch`｜🟠

**用途**：抓取一个 URL，用 `prompt` 对其内容做提炼后回填。

```rust
#[derive(Deserialize, JsonSchema)]
struct WebFetchArgs {
    /// 要抓取的 URL
    url: String,
    /// 对抓到内容运行的提示
    prompt: String,
}
struct WebFetchOutput {
    bytes: u64,           // 抓取内容字节数
    code: u32,            // HTTP 状态码
    code_text: String,    // HTTP 状态文本
    result: String,       // prompt 应用于内容后的结果
    duration_ms: u64,     // 抓取+处理耗时
    url: String,          // 实际抓取的 URL
}
```

### `web_search`｜🟠

**用途**：联网搜索，可按域名白/黑名单过滤。

```rust
#[derive(Deserialize, JsonSchema)]
struct WebSearchArgs {
    /// 搜索词
    query: String,
    /// 仅保留这些域名的结果
    allowed_domains: Option<Vec<String>>,
    /// 永不包含这些域名的结果
    blocked_domains: Option<Vec<String>>,
}
struct WebSearchOutput {
    query: String,
    results: Vec<SearchResult>,  // 每条含 title/url（可含 tool_use_id 分组）
    duration_seconds: f64,
}
```

## 交互

human-in-the-loop 的澄清工具，让 agent 在执行中反问用户。**🟠**。

### `ask_user_question`｜🟠

**用途**：执行中向用户抛出 1-4 个带选项的澄清问题；答案由权限系统回填。

```rust
#[derive(Deserialize, JsonSchema)]
struct AskUserQuestionArgs {
    /// 1-4 个问题
    questions: Vec<Question>,
}
struct Question {
    question: String,           // 完整问题
    header: String,             // 极短标签（≤12 字符）
    options: Vec<QuestionOption>,// 2-4 个选项
    multi_select: bool,         // 是否允许多选
}
struct QuestionOption {
    label: String,              // 选项显示文本（1-5 词）
    description: String,        // 该选项含义说明
}

// 输出：回显问题 + answers（问题文本 → 答案；多选以逗号连接）
struct AskUserQuestionOutput {
    questions: Vec<Question>,
    answers: std::collections::HashMap<String, String>,
}
```

这条工具与 [权限模型](/sdk/permissions) 的审批/输入回填链路强相关。

## 规划/任务

让模型自己维护一份任务清单。历史上是单一的 `todo_write`，**现已被 `task_*` 四件套取代**（更结构化、可依赖、可指派）。整组 **🟠**。

### `todo_write`｜🟠（被 task 系取代）

**用途**：整份覆写一份 todo 清单。**已被 `task_*` 取代**，仅为兼容登记。

```rust
#[derive(Deserialize, JsonSchema)]
struct TodoWriteArgs {
    todos: Vec<TodoItem>,
}
struct TodoItem {
    content: String,        // 任务描述
    status: String,         // "pending" | "in_progress" | "completed"
    active_form: String,    // 进行时描述
}
// 输出：{ message, stats: { total, pending, in_progress, completed } }
```

### `task_create`｜🟠

**用途**：新建一个任务，返回分配到的 id。

```rust
#[derive(Deserialize, JsonSchema)]
struct TaskCreateArgs {
    subject: String,                // 简短标题
    description: String,            // 详细正文
    active_form: Option<String>,    // 进行时标签
    metadata: Option<serde_json::Value>, // 任意调用方元数据
}
// 输出：{ task: { id, subject } }
```

### `task_update`｜🟠

**用途**：按 id 局部修改任务（状态、依赖、指派……）。

```rust
#[derive(Deserialize, JsonSchema)]
struct TaskUpdateArgs {
    task_id: String,
    status: Option<String>,          // pending|in_progress|completed|deleted
    subject: Option<String>,
    description: Option<String>,
    active_form: Option<String>,
    add_blocks: Option<Vec<String>>,    // 本任务新阻塞的任务 id
    add_blocked_by: Option<Vec<String>>,// 新阻塞本任务的任务 id
    owner: Option<String>,
    metadata: Option<serde_json::Value>,
}
// 输出：{ success, task_id, updated_fields, error?, status_change? }
```

### `task_get`｜🟠

**用途**：按 id 读取单个任务全貌。

```rust
#[derive(Deserialize, JsonSchema)]
struct TaskGetArgs {
    task_id: String,
}
// 输出：{ task: { id, subject, description, status, blocks, blocked_by } | None }
```

### `task_list`｜🟠

**用途**：列出全部任务的摘要视图。

```rust
#[derive(Deserialize, JsonSchema)]
struct TaskListArgs {}   // 无入参
// 输出：{ tasks: [ { id, subject, status, owner?, blocked_by } ] }
```

## 子 agent

模型可**调用**的子 agent 生成工具——让主 agent 把一段自包含子任务派给一个专门子 agent 跑完再收敛结果。**🟠**。

命名说明：`agent`（旧名 `task`，仍作别名接受）。

::: warning 与配置类型 `AgentDefinition` 区分
本页的 `agent` 是**模型可调用的运行时工具**（模型主动拉起子 agent）。它与**配置态的子 agent 定义** `AgentDefinition`（在 [Options/agents](/sdk/options) 里声明可用的子 agent 类型）是两回事：后者是「有哪些子 agent 可选」，前者是「模型现在就调起其中一个」。
:::

### `agent`｜🟠

**用途**：拉起一个指定类型的子 agent 执行子任务。

```rust
#[derive(Deserialize, JsonSchema)]
struct AgentArgs {
    /// 任务的极短描述（3-5 词）
    description: String,
    /// 交给子 agent 执行的具体任务
    prompt: String,
    /// 使用的专门子 agent 类型（对应某个 AgentDefinition）
    subagent_type: String,
}
struct AgentOutput {
    result: String,                  // 子 agent 的最终结果
    usage: Option<serde_json::Value>,// token 用量
    total_cost_usd: Option<f64>,     // 估算总成本
    duration_ms: Option<u64>,        // 执行耗时
}
```

## MCP 资源

对已挂载 MCP server 暴露的**资源**（非工具）做发现与读取。**🟠**。MCP 工具本身的挂载见 [自定义工具 · MCP](/sdk/tools)。

### `list_mcp_resources`｜🟠

**用途**：列出（可按 server 过滤）可用的 MCP 资源。

```rust
#[derive(Deserialize, JsonSchema)]
struct ListMcpResourcesArgs {
    /// 可选：按 server 名过滤
    server: Option<String>,
}
struct ListMcpResourcesOutput {
    resources: Vec<McpResource>, // 每条含 uri/name/description?/mime_type?/server
    total: u64,
}
```

### `read_mcp_resource`｜🟠

**用途**：按 server + uri 读取一个 MCP 资源的内容。

```rust
#[derive(Deserialize, JsonSchema)]
struct ReadMcpResourceArgs {
    /// MCP server 名
    server: String,
    /// 要读取的资源 URI
    uri: String,
}
struct ReadMcpResourceOutput {
    contents: Vec<McpContent>,   // 每条含 uri/mime_type?/text?/blob?
    server: String,
}
```

## 规划模式

配合权限的 **plan 模式**：agent 先只读地做出方案，经用户批准后再退出计划模式动手执行。**🟠**。

### `exit_plan_mode`｜🟠

**用途**：提交一份方案供用户批准，批准后退出 plan 模式。

```rust
#[derive(Deserialize, JsonSchema)]
struct ExitPlanModeArgs {
    /// 交给用户审批的方案
    plan: String,
}
struct ExitPlanModeOutput {
    message: String,
    approved: Option<bool>,  // 用户是否批准
}
```

plan 模式作为一种权限模式，其判定与「只读探索 → 批准 → 执行」的流转见 [权限模型](/sdk/permissions)。

## 合理不纳入

- **`notebook_edit`｜⚪ 不纳入**：Jupyter notebook 单元格编辑是 **Jupyter 专属、场景 niche** 的能力，不属于通用 agent SDK 的核心内置面。需要时可作为一个自定义工具或 MCP 能力按需接入，而非默认目录成员。

## 相关

- [自定义工具](/sdk/tools) —— 怎么**写**并挂载自己的工具（`#[tool]` / `FunctionTools` / MCP）
- [Options 配置](/sdk/options) —— 子 agent 定义 `AgentDefinition`、工具装配旋钮
- [权限模型](/sdk/permissions) —— 命令沙箱、plan 模式、审批与输入回填
- [消息模型](/sdk/messages) —— 工具调用/结果在消息流里的呈现
- [Python：内置工具目录](/sdk-py/builtin-tools) —— 本页的 Python 镜像
