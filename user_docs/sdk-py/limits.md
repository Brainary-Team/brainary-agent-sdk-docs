---
outline: 2
---

# 边界与路线图（Python）

> **读完本页你能**：看懂 Python 版 brainary-agent-sdk 的实现状态、它与 Rust 版的 parity 关系，以及接口全表面 × Brainary 决策的覆盖矩阵。

::: warning 规划状态
Python 版 brainary-agent-sdk **本身尚未实现**（Rust 版在独立分支，Python 端口待排期）。本章记录的是**规划中的 Python 接口面**——镜像 Rust 版、命名沿用 Brainary 名，写法遵循 Python 惯用法。下表的「决策」列是**接口层面**的裁剪（与 Rust 版一致），「Python 实现」整体归路线图。
:::

## Rust ↔ Python parity

| 维度 | 说明 |
| --- | --- |
| **接口清单** | 单一真源，Rust / Python 共享（见方案第 4 节）。两语言同增同减 |
| **命名** | 沿用 Brainary 名（`query` / `BrainaryClient` / `Options`），跨语言一致 |
| **形态差异** | 仅签名风格：Rust 的 `Result`/借用 ↔ Python 的异常/`async with`；Rust 的枚举 `match` ↔ Python 的 `isinstance` |
| **实现进度** | Rust 版与 Python 版当前均为 🟠【规划中，未完成】、尚未实现（Rust 在独立分支，Python 端口待排期） |

**状态说明**：brainary-agent-sdk 当前**全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；下方给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非占位草案。（⚪ = 暂缓 / 不纳入，非交付接口。）

## 接口层面明确不做（与 Rust 一致）

| 能力 | 状态 | 归属 | 说明 |
| --- | --- | --- | --- |
| token 级流式输出 | 🟠 | 上游 | 现为**步级**流：每完成一步产出一条 `Message` |
| 跨进程 resume（从 transcript 续跑） | 🟠 | 上游 | 底层无「从历史重建 agent」构造器；进程内 resume 规划支持 |
| 步内中断 | 🟠 | 上游 | 现为**步边界**协作式中断 |
| 真实 cost 计量 | 🟠 | 上游 | `total_cost_usd` / `usage` 恒 `None`，类型已就位，见 [消息模型](/sdk-py/messages#cost) |
| 结构化 `tool_use` / `tool_result` 填充 | 🟠 | 上游 | 类型已建齐，v1 不填充 |
| 自动压缩 | 🟠 | core | 旋钮就位，落地由 core 拥有 |
| 手动 `compact()` | ⚪ | 不暴露 | **故意**不给（footgun） |

## 覆盖矩阵：接口全表面与决策 {#coverage-matrix}

这张表把 agent SDK 的**全部**候选公开接口过一遍，**站在「编码智能体 agent SDK」这一目标工具的位置**逐行裁决，每行给出 Brainary 的处置决策与一句理由。它是本站**权威**的「扫过完整表面 × 我方决策」总表：凡判 ⚪（暂缓/仅登记）的都给出明确理由（多为 CLI 子进程内部管线、已退役接口或工具宇宙不同者），而非把边缘接口一概推迟——传输、流事件、限流、后台任务消息、**命令沙箱**、插件、Hooks、内置工具目录、设置来源等面均从目标工具视角逐项重判并登记在下。Python 与 Rust **决策一致**（同一接口清单）。

**决策标签**：🟠 纳入本站交付面（【规划中，未完成】——架构已规划、尚未实现） · ⬇️ 下沉核心层（非本站门面职责） · ⚪ 暂缓 / 不纳入（仅登记，附理由）。凡「纳入」的接口当前一律为 🟠，不再细分实现档位。

### 入口与函数

| 接口 | 决策 | 一句理由 / 去处 |
| --- | --- | --- |
| `query()` | 🟠 | 一次性入口，[两个入口](/sdk-py/query-and-client) |
| 有状态多轮客户端 | 🟠 | → `BrainaryClient`，[两个入口](/sdk-py/query-and-client) |
| `tool()` | 🟠 | `@tool` 装饰器，[自定义工具](/sdk-py/tools) |
| `create_sdk_mcp_server()` | 🟠 | 命名能力单元（对应 Rust `FunctionTools`），[自定义工具](/sdk-py/tools#create-sdk-mcp-server) |
| `list_sessions` / `get_session_messages` / `get_session_info` / `rename_session` | 🟠 | 待跨进程持久化底座，[会话管理](/sdk-py/sessions) |
| `tag_session` | ⚪ | 可选 |

### 类型

| 接口 | 决策 | 一句理由 / 去处 |
| --- | --- | --- |
| 统一配置对象 | 🟠 | `Options`，[Options](/sdk-py/options) |
| `SystemPromptPreset` | 🟠 | 系统提示三来源，[Options](/sdk-py/options#系统提示-systemprompt) |
| `Message` / `ContentBlock` | 🟠 | 一对一镜像，[消息模型](/sdk-py/messages) |
| `billing_cap` / `total_cost_usd` / `usage` | 🟠 | 成本面，`billing_cap` 规划就位、值待上游，[成本](/sdk-py/messages#cost) |
| `PermissionMode` / `CanUseTool` / `PermissionResult` | 🟠 | 控制面三件套，占位，[权限模型](/sdk-py/permissions)（已从占位改写为完整规范） |
| `ToolPermissionContext` | 🟠 | `CanUseTool` 回调自身的入参，属控制面 CORE，占位，[权限模型](/sdk-py/permissions) |
| `PermissionUpdate` / `PermissionRuleValue` | 🟠 | 运行期改规则并持久化的**公开**机制（非 CLI 内部），占位，[权限模型](/sdk-py/permissions) |
| `AgentDefinition`（子 agent） | 🟠 | 提升为 SDK 表面 `Options.agents`：程序化子 agent 是这类编码智能体的头等特性；深度装配仍可交叉引用 核心层 |
| `ToolAnnotations` | 🟠 | 工具行为提示，[自定义工具](/sdk-py/tools#toolannotations-工具行为提示-架构占位) |
| `McpServerConfig` 家族 | 🟠 | `mcp_server()` 糖只收 URL；需补 stdio `args`/`env` 与**鉴权 `headers`**（缺 headers 无法配置需鉴权的远程 MCP），MCP |
| 语义错误模型 | 🟠 | `BrainaryError` 异常类树（`BuildError` / `RateLimitError` / `ToolExecutionError` …），[错误处理](/sdk-py/errors) |
| `CLINotFoundError` / `CLIConnectionError` / `ProcessError` / `CLIJSONDecodeError` | ⚪ | CLI 子进程传输产物（缺二进制/连不上/非零退出/JSON 解析失败）；brainary-agent-sdk 是**进程内库**，无此层（OUT），[错误处理](/sdk-py/errors#cli-error-family-out) |
| Hook types | 🟠 | 确定性治理层，整只子系统已成规范，占位，[Hooks](/sdk-py/hooks) |
| `OutputFormat` / `ThinkingConfig` / `EffortLevel` | 🟠 | 结构化输出对库调用尤其有用；thinking/effort 是现代 agent 控制面，多归 `llm_settings`，占位 |
| `SettingSource` / setting_sources | 🟠 | 是否加载 user/project/local 设置（含项目记忆文件）；传空 = hermetic，利于 CI，占位 |
| `ToolsPreset` | ⚪ | 编码智能体预设的工具宇宙与 Brainary 不同，不移植（OUT） |
| `SdkBeta` | ⚪ | 已退役，仅登记（OUT） |
| `Transport`（自定义传输） | ⚪ | CLI 子进程逃生口；Brainary 内部自持传输，不作公共旋钮 |
| `StreamEvent`（partial 消息） | 🟠 | 归 token 级流式——现为步级，类型面待上游 |
| `RateLimitEvent` / `RateLimitInfo` | 🟠 | 面向托管模型的 agent SDK 应暴露限流状态以便退避，占位 |
| 后台任务消息（`TaskStarted` / `TaskProgress` / `TaskNotification` + `TaskUsage`） | 🟠 | 随 `stop_task`；v1 无后台任务模型 |
| `SandboxSettings` 家族 | 🟠 | 宿主内**命令沙箱**：约束 bash 工具的文件/命令/网络，占位。与 PoA/wasm 隔离整只 `.poa` 是不同概念，两者都要 |
| `SdkPluginConfig` / plugins | 🟠 | SDK **程序化**加载本地插件包（commands/agents/mcp）；「CLI 专属」判断有误，占位 |

### 内置工具与授权

| 接口 | 决策 | 一句理由 / 去处 |
| --- | --- | --- |
| **内置工具目录**（Read/Write/Edit/Bash/Glob/Grep/WebFetch/WebSearch/Agent 等，Brainary 原生名） | 🟠 | 编码智能体 SDK 的定义性面：文件类规划由 `FolderPrimitive` 装配（schema 待精化），shell/web/交互/任务/子 agent 均规划中，[内置工具目录](/sdk-py/builtin-tools) |
| `allowed_tools` / `disallowed_tools` | 🟠 | 声明式授权清单（可用性 ≠ 授权），占位，[权限模型](/sdk-py/permissions) |
| `permission_mode`（6 模）/ `CanUseTool` / `PermissionResult` | 🟠 | 控制面三件套，占位，指向已改写为完整规范的 [权限模型](/sdk-py/permissions) |

### 运行时控制（客户端方法）

| 接口 | 决策 | 一句理由 |
| --- | --- | --- |
| `connect` / `query` / `interrupt` / `disconnect` | 🟠 | `async with` + `query` / `receive_response` + `await client.interrupt()` |
| `set_model` / `set_permission_mode` / `rewind_files` | 🟠 | 运行时切换/文件检查点未做 |
| `get_mcp_status` / `reconnect_mcp_server` / `toggle_mcp_server` | 🟠 | MCP 运行时控制未做 |
| `stop_task` | 🟠 | 无后台任务模型 |
| `get_server_info` | 🟠 | 部分由只读 getter 覆盖 |

> **Brainary 独有**：`step_once` / `revert`（手动单步回退）、`export_transcript`（只读快照）、`approx_context_tokens` / `context_window`——见 [两个入口](/sdk-py/query-and-client#brainaryclient-只读检视与单步)。

## 相关

- [总览](/sdk-py/overview) · [消息模型](/sdk-py/messages#cost)
- [会话管理](/sdk-py/sessions) 🟠 · [权限模型](/sdk-py/permissions) 🟠
- 对照 Rust：[边界与路线图](/sdk/limits)
