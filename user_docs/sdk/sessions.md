---
outline: 2
---

# 会话管理（架构已规划）

> **读完本页你能**：分清「进程内 resume」「transcript 导出」「跨进程 session 管理」这三件常被混为一谈的事，看懂 Brainary 已**定形**的一组会话管理函数（函数名、参数、返回类型都已承诺），以及为什么 v1 尚未落地它们——差的只是底层那层跨进程持久化存储。

::: warning 本页描述的是「架构已规划、尚未实现」的接口（🟠）
本页的**函数签名与字段集已经定形并承诺**，不再是「待对齐后定稿」的草稿：函数名、参数、返回结构在 Rust 与 Python 两侧**逐参数对齐**、就此固定。仍标 🟠，是因为它们**当前 v1 未实现**——尚未落地的是底层那层**跨进程持久化存储**（会话落盘、编号、索引），这一块由底层（子乔）拥有。函数面本身不再变动。你现在能用的会话能力只有：进程内多轮 resume（[BrainaryClient](/sdk/query-and-client)）与只读快照导出（[transcript](/sdk/transcript)）。
:::

## 三件事，别混淆

「会话」在不同语境下指三件**不同**的事。Brainary v1 只落地了前两件，第三件是本页规划的对象：

| 能力 | 是什么 | v1 状态 | 在哪 |
| --- | --- | --- | --- |
| **进程内 resume** | 同一个 `BrainaryClient` 活着期间，多轮对话上下文自动累积 | 🟠 规划中 | [两个入口](/sdk/query-and-client) |
| **transcript 导出** | 把当前会话导成可序列化的只读快照（**只导出、不可续跑**） | 🟠 规划中 | [会话导出](/sdk/transcript) |
| **跨进程 session 管理** | 把**多份历史会话**持久化到磁盘，之后 list / 查看 / 重命名 / 打标签 / 载回续跑 | 🟠 未实现 | 本页 |

> 关键：**session 管理 ≠ resume**，是两件事——只是都压在「跨进程持久化」这一未做的底座上。这里的 session 指**磁盘持久化的历史会话**（`session_id` + 会话文件，支持列举、重命名、打标签、管理多份历史）；Brainary v1 两层都没有。

## 定形的会话函数

Brainary 定义一组 module 级会话管理函数，作为已承诺的接口形态。它们统一做成 **async free function、返回 `Result`**（与 `query()` / `connect()` 的风格一致）：

| 函数 | 作用 | 状态 |
| --- | --- | --- |
| `list_sessions(...)` | 列出历史会话（可按目录过滤、分页） | 🟠 |
| `get_session_messages(session_id, ...)` | 读某会话的消息（复用 transcript 类型，可分页） | 🟠 |
| `get_session_info(session_id, ...)` | 读某会话的元信息（`SessionInfo`） | 🟠 |
| `rename_session(session_id, title, ...)` | 重命名会话（设自定义标题） | 🟠 |
| `tag_session(session_id, tag, ...)` | 给会话打标签（`None` 清除） | 🟠 |

> 这些是 **free function**，形态就此固定。仍在底层拥有、尚未落地的，只有它们背后那层**跨进程持久化存储**——把多份会话落盘、编号、按目录索引。函数面不随实现变动。

## 会话函数签名（已承诺）

以下签名**已定形**，与 [Python 侧](/sdk-py/sessions)逐参数对齐。均为 async、返回 `Result`、只用 SDK 自有可序列化类型（不外泄 llmy 类型）：

```rust
// ⚠️ 以下为架构已规划、v1 未实现的接口（🟠）；签名已定形，差的是底层持久化存储。

/// 列出历史会话；按 last_modified 降序（最新在前）。
///
/// - `directory`：只列某项目目录下的会话；`None` 则跨全部项目。
/// - `limit`：最多返回多少条；`None` 不限。
/// - `offset`：从头跳过多少条（配合 limit 分页）。
pub async fn list_sessions(
    directory: Option<&Path>,
    limit: Option<usize>,
    offset: usize,
) -> Result<Vec<SessionInfo>>;

/// 读取某份历史会话的消息（复用 transcript 的 SDK 自有类型）。
///
/// - `directory`：在哪个项目目录查找；`None` 则跨全部项目。
/// - `limit` / `offset`：消息级分页。
pub async fn get_session_messages(
    session_id: &str,
    directory: Option<&Path>,
    limit: Option<usize>,
    offset: usize,
) -> Result<Vec<TranscriptMessage>>;

/// 读取某份历史会话的元信息；未找到返回 `Ok(None)`。
pub async fn get_session_info(
    session_id: &str,
    directory: Option<&Path>,
) -> Result<Option<SessionInfo>>;

/// 重命名一份历史会话（写入自定义标题；重复调用以最后一次为准）。
/// `title` 去空白后不可为空，否则返回错误。
pub async fn rename_session(
    session_id: &str,
    title: impl Into<String>,
    directory: Option<&Path>,
) -> Result<()>;

/// 给一份历史会话打标签；`None` 清除标签（重复调用以最后一次为准）。
pub async fn tag_session(
    session_id: &str,
    tag: Option<&str>,
    directory: Option<&Path>,
) -> Result<()>;
```

> 接口约定：Brainary 统一成 **async + `Result`** 以贴合 SDK 其余入口；`directory` 用 `&Path`、分页用 `usize`。worktree 展开开关（`include_worktrees`）暂不进面，留待底层决定默认行为。

## SessionInfo：完整字段集

`SessionInfo` 是一份历史会话的元信息（SDK 自有、可序列化）。字段集**已恢复完整**——这些字段正是让「列一屏历史会话」在编码工作流里真正有用的东西：

```rust
/// 一份历史会话的元信息（SDK 自有、可序列化）。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SessionInfo {
    pub session_id: String,
    pub summary: Option<String>,
    pub created_at: Option<i64>,
    pub last_modified: i64,
    pub num_turns: usize,
    pub cwd: Option<String>,
    pub git_branch: Option<String>,
    pub file_size: Option<u64>,
    pub first_prompt: Option<String>,
    pub custom_title: Option<String>,
    pub tag: Option<String>,
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `session_id` | `String` | 会话唯一标识，是整套会话 API 的 join key（见下「先决条件」） |
| `summary` | `Option<String>` | 展示标题：自定义标题 → 自动摘要 → 首条提示，逐级回退 |
| `created_at` | `Option<i64>` | 创建时间（毫秒时间戳） |
| `last_modified` | `i64` | 最后修改时间（毫秒时间戳）；列表按它降序排 |
| `num_turns` | `usize` | 会话累计轮数 |
| `cwd` | `Option<String>` | 会话的工作目录 |
| `git_branch` | `Option<String>` | 会话结束时所在的 git 分支 |
| `file_size` | `Option<u64>` | 会话文件字节数（远端存储后端为 `None`） |
| `first_prompt` | `Option<String>` | 会话里第一条有意义的用户提示 |
| `custom_title` | `Option<String>` | 用户设置的会话标题（`rename_session` 写入） |
| `tag` | `Option<String>` | 用户设置的标签（`tag_session` 写入） |

> **为什么字段要这么全？** `git_branch` / `cwd` / `last_modified` 是让列表**在编码工作流里可用**的关键：一屏历史会话，靠「哪个分支、哪个目录、最近何时动过」才能快速认出「就是上周那个重构 auth 的会话」，而不是对着一串 UUID 干瞪眼。

## 先决条件：session id 访问器

整套会话 API 的 join key 是 `session_id`——`get_session_messages` / `get_session_info` / `rename_session` / `tag_session` 第一个参数都是它。而 **Brainary 当前的 `BrainaryClient` 还没有暴露「当前会话 id」的访问器**：进程内 resume 不需要 id，所以从没做过。

因此 **`get_server_info`（见 [两个入口](/sdk/query-and-client)）是这一整套会话 API 的先决条件**——它返回 session id 与能力信息，是把「活着的进程内会话」和「磁盘上的历史会话」对上号的那把钥匙。没有 session id 访问器，就无法在运行结束后用同一个 id 去 list / rename / resume。

## resume 家族：三种续跑

会话管理的另一半是「载回续跑」。Brainary 规划三个入口（前两者的**进程内**形态已 🟠，跨进程形态 🟠）：

| 入口 | 语义 | 状态 |
| --- | --- | --- |
| `continue_conversation` | 续**最近一份**会话（不必给 id） | 🟠 跨进程 |
| `resume(session_id)` | 按 **session id** 续某份具体会话 | 🟠 进程内 resume（规划中）/ 跨进程载回（规划中） |
| `fork_session` | resume 时**分叉**到一个新 session id，原会话不动 | 🟠 |

这三者作为 [Options](/sdk/options) 上的装配旋钮承诺（跨进程形态待底层持久化就位）：

```rust
// ⚠️ 跨进程形态 v1 未实现（🟠）；进程内 resume 已 🟠（见 /sdk/query-and-client）。
Options::builder()
    .continue_conversation(true)          // 续最近一份历史会话
    // 或：
    .resume(session_id)                   // 按 id 续某份会话
    .fork_session(true)                   // resume 时分叉到新 session id
    .build()?;
```

- **进程内 resume（规划中）**：同一个 `BrainaryClient` 活着期间多轮上下文自动累积，无需 id（见 [两个入口](/sdk/query-and-client)）。
- **跨进程 resume 未实现**：把磁盘上一份历史会话载回成能继续跑的 agent，卡在下面「依赖的底座」的 transcript resume 上。
- **`fork_session`** 用于「从某历史会话分叉出一条新支线」：以它为起点续跑，但落到一个**新** session id，原会话保持只读不变。

## 运行时客户端控制

除了会话函数，`BrainaryClient` 还规划两个**运行时切换**方法（`set_model` / `set_permission_mode`），承诺形态、v1 未实现（🟠）：

```rust
// ⚠️ v1 未实现（🟠）；当前需重建 client 才能换模型 / 权限模式。
impl BrainaryClient {
    /// 运行时切换模型。
    pub async fn set_model(&mut self, model: ModelSelection) -> Result<()>;

    /// 运行时切换权限模式。
    pub async fn set_permission_mode(&mut self, mode: PermissionMode) -> Result<()>;
}
```

- `set_model`：当前模型在 `Options` 装配时固定，运行时切换需重建 client；此方法把「不重建 client 就换模型」提上路线图。
- `set_permission_mode`：整套权限模式（`plan` / `acceptEdits` / …）本身也尚未落地，语义与取值见 [权限模型](/sdk/permissions)。

## 文件检查点 rewind_files

`rewind_files` 是**文件级**检查点/恢复：把工作区文件恢复到「某条用户消息当时」的状态。它与 `revert()` 是**两码事**，别混：

| 能力 | 粒度 | 恢复什么 | 状态 |
| --- | --- | --- | --- |
| `revert()` | **步级** | 撤掉最近一步对话（会话状态回退一步） | 🟠 规划中 |
| `rewind_files(message_id)` | **文件级** | 把磁盘上的文件回滚到某条用户消息时的快照 | 🟠 未实现 |

```rust
// ⚠️ v1 未实现（🟠）；需要一层文件检查点开关。
impl BrainaryClient {
    /// 把工作区文件恢复到指定用户消息当时的状态。
    pub async fn rewind_files(&mut self, user_message_id: &str) -> Result<()>;
}
```

对一个**编码 agent** 而言，这是 **ADAPT-CORE**（值得下沉到 core 层实现）：agent 改坏了一批文件、想整体退回到某一轮之前——这正是编码工作流的核心撤销语义，比步级 `revert()` 更贴近「我要回到改动之前的磁盘状态」。它依赖一层文件检查点存储，逐项决策见 [边界与路线图](/sdk/limits)。

## 依赖的底座

要实现上面这些，需要先有一层 v1 未做的**跨进程持久化**底座，它本身又分两块（对应上面「三件事」里未做的第三件）：

1. **session 索引**：把多份会话落盘、编号、按目录索引，可列举 / 查元信息 / 重命名 / 打标签——即本页 `list_sessions` / `get_session_info` / `rename_session` / `tag_session` 背后的存储层，归底层拥有。
2. **transcript resume**：把导出的 transcript **载回**一个能继续跑的 agent——llmy 目前**没有**「用历史重建 agent」的构造器，故 v1 无法续跑（见 [会话导出](/sdk/transcript#⚠️-仅导出-不可续跑)）。

两块都归入路线图，逐项决策见 [边界与路线图](/sdk/limits) 的覆盖矩阵。

## 相关

- [两个入口：BrainaryClient](/sdk/query-and-client) —— 进程内 resume（🟠 规划中）、`get_server_info` 与运行时控制
- [会话导出 transcript](/sdk/transcript) —— 只读快照，只导出不续跑
- [权限模型](/sdk/permissions) —— 另一个架构已规划、未实现的面
- [边界与路线图](/sdk/limits) —— 覆盖矩阵与里程碑
- 对照 Python：[会话管理](/sdk-py/sessions)
