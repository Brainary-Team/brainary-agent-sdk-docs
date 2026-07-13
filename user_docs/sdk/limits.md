---
outline: 2
---

# v1 边界与路线图

> **读完本页你能**：分清 brainary-agent-sdk v1 明确不做的事、它们各自归到哪个里程碑（llmy 上游 / core），看懂 **接口全表面 × Brainary 决策的覆盖矩阵**，以及「SDK 是门面不是内核」这条裁决背后的理由。

## 概念简述

brainary-agent-sdk v1（M1–M4 已实现并真机验证）忠实交付了：一次性 + 多轮入口、统一 `Options`、轻量自定义工具、进程内 resume、步级流、步边界中断、只读 transcript 导出。

一批能力 v1 **明确不做**——但要点是：**类型已建齐，仅数据受限**。消息模型的形态（四类消息 × 四种内容块）现在就完整摆好，`#[non_exhaustive]` 保证后续加法不破坏；v1 只是不去**填充**那些依赖上游的数据。

**状态图例（全站统一 4 态）**：🟢 已实现 · 🟡 类型/旋钮就位待上游 · 🟠 架构已规划未实现 · ⚪ 暂缓/仅登记

## v1 明确不做

| 能力 | 状态 | 归属 | 说明 |
| ---- | ------- | ---- | ---- |
| token 级流式输出 | 🟡 | llmy 上游 | 现为**步级**流：每完成一步产出一条 `Message`；token 级待上游 |
| 跨进程 resume（从 transcript 续跑） | 🟠 | llmy 上游 | llmy 无「从历史重建 agent」的构造器；进程内 resume 已由 `BrainaryClient` 支持 |
| 步内中断 | 🟡 | llmy 上游 | 现为**步边界**协作式中断；llmy 无步内取消 |
| 真实 cost 计量 | 🟡 | llmy 上游 | `ResultMessage.usage` / `total_cost_usd` 恒 `None`，类型已就位（见 [消息模型](/sdk/messages#cost)） |
| 结构化 `tool_use` / `tool_result` 块填充 | 🟡 | llmy 上游 | `ContentBlock::ToolUse/ToolResult/Thinking` 类型已建齐，**v1 不填充**；工具调用现只给 `AssistantMessage.requested_tools` 粗信号 |
| 自动压缩（`Options.auto_compact`） | 🟡 | core | 旋钮就位，v1 仅 `AutoCompact::Off` 有意义 |
| 手动 `compact()` | ⚪ | 不暴露 | **故意**不给（footgun，见下） |

`Message` 各字段的逐项填充度对照表见 [消息模型](/sdk/messages)。

## 待 llmy 上游（原 M5）

以下都卡在 llmy 上游能力，llmy 补齐后 SDK 加法式填入，无破坏：

- **token 级流**：把步级流细化到 token。
- **跨进程真 resume**：从导出的 transcript 载入新进程继续跑。
- **步内中断**：不必等当前步跑完即可取消。
- **真实 cost**：填充 `ResultMessage.usage` 与 `total_cost_usd`。
- **结构化 `tool_use` / `tool_result` 填充**：把工具调用/结果作为结构化 `ContentBlock` 真正填充出来，取代当前的 `requested_tools` 粗信号。

## 待 core（原 M6）

- **自动压缩策略**：上下文治理的自动压缩由 **core 拥有**并实现；`Options.auto_compact` 旋钮 v1 已就位，落地后翻开 `Auto` / `Threshold(_)` 即可用。
- 在此之前，v1 的上下文治理靠**溢出护栏**兜底（逼近窗口以 `StopReason::ContextExhausted` 明确停），见 [中断、护栏与上下文](/sdk/interrupt-and-guardrails)。

## 裁决理由

- **SDK 是门面，不是内核**。凡触及核心语义（compaction、上下文治理）的决策权在 **core**，不在门面 SDK。因此自动压缩策略归 M6/core，SDK 只暴露旋钮。
- **手动 `compact()` 故意不暴露**：手动压缩是 footgun——会让上下文治理的责任在门面与内核之间割裂。上下文治理统一走「core 拥有的自动压缩策略（M6）＋ v1 的溢出护栏」，而不是把一个易误用的手动钮塞给调用方。
- **类型先行**：把消息模型、`usage`、结构化块等类型现在就建齐并标 `#[non_exhaustive]`，是为了 M5/M6 能纯加法式填数据，调用方代码不必因为版本升级而改。

## 覆盖矩阵：接口全表面与决策 {#coverage-matrix}

这张表把 agent SDK 的**全部**公开接口过一遍，**站在「Brainary-Code-like agent SDK」这一目标工具的位置**逐行裁决，每行给出 Brainary 的处置决策与一句理由。它是本站**权威**的「扫过完整表面 × 我方决策」总表：凡判 ⚪（暂缓/仅登记）的都给出明确理由（多为 CLI 子进程内部管线、已退役接口或工具宇宙不同者），而非把边缘接口一概推迟——传输、流事件、限流、后台任务消息、**命令沙箱**、插件、Hooks、内置工具目录、设置来源等面均从目标工具视角逐项重判并登记在下。

**决策标签**：✅ 纳入（已实现） · 🟢 已实现（本站原生面） · 🟡 类型就位待上游 · 🟠 占位（架构规划、未实现） · ⬇️ 下沉核心层 · ⚪ 暂缓（仅登记，附理由）

### 入口与函数

| 接口 | 决策 | 一句理由 / 去处 |
| --- | --- | --- |
| `query()` | ✅ | 一次性入口 = 会议的 QE，[两个入口](/sdk/query-and-client) |
| `BrainaryClient` | ✅ | 有状态多轮 = 会议的 client，[两个入口](/sdk/query-and-client) |
| `#[tool]`（宏） | ✅ | `#[tool]` 宏，[自定义工具](/sdk/tools) |
| `FunctionTools`（命名能力单元） | ✅ | `FunctionTools`（命名能力单元），[自定义工具](/sdk/tools) |
| `list_sessions` / `get_session_messages` / `get_session_info` / `rename_session` | 🟠 | 架构要、实现待跨进程持久化底座，[会话管理](/sdk/sessions) |
| `tag_session` | ⚪ | 可选，登记待议 |

### 类型

| 接口 | 决策 | 一句理由 / 去处 |
| --- | --- | --- |
| `Options` | ✅ | `Options` builder，[Options](/sdk/options) |
| `SystemPrompt` | ✅ | `SystemPrompt` 枚举（Default/Inline/TemplateFile），[Options](/sdk/options#系统提示-systemprompt) |
| `Message` / `ContentBlock` 及各变体 | ✅ | 各变体一一就位，[消息模型](/sdk/messages) |
| `billing_cap` / `ResultMessage.total_cost_usd` | 🟡 | 成本面：`billing_cap` 已生效、`total_cost_usd` 恒 `None` 待上游，[成本](/sdk/messages#cost) |
| `usage`（token 计量） | 🟡 | 类型就位、恒 `None` 待上游 |
| `PermissionMode` / `CanUseTool` / `PermissionResult` | 🟠 | 控制面表面三件套，占位，[权限模型](/sdk/permissions)（已从占位改写为完整规范） |
| `ToolPermissionContext` | 🟠 | `CanUseTool` 回调自身的入参，属控制面 CORE，占位，[权限模型](/sdk/permissions) |
| `PermissionUpdate` / `PermissionRuleValue` | 🟠 | 运行期改规则并持久化的**公开**机制（非 CLI 内部），占位，[权限模型](/sdk/permissions) |
| `AgentDefinition`（子 agent） | 🟠 | 提升为 SDK 表面 `Options.agents`：程序化子 agent 是本工具头等特性；深度装配仍可交叉引用 核心层 |
| `ToolAnnotations` | 🟠 | 工具行为提示，供权限层用，占位，[自定义工具](/sdk/tools#toolannotations-工具行为提示-架构占位) |
| `McpServerConfig` 家族（Stdio/SSE/Http） | 🟡 | `mcp_server()` 糖目前只收 URL；需补 stdio `args`/`env` 与**鉴权 `headers`**（缺 headers 无法配置需鉴权的远程 MCP），MCP |
| `BrainaryError`（语义错误模型） | ✅ | `BrainaryError` 枚举（构建期领域变体 🟢）+ `ErrorCategory` 可恢复性分类（🟠），[错误处理](/sdk/errors) |
| `CLINotFoundError` / `CLIConnectionError` / `ProcessError` / `CLIJSONDecodeError` 一族 | ⚪ | 这些是 CLI 子进程传输方式的副作用（缺二进制/连不上/非零退出/JSON 解析失败）；brainary-agent-sdk 是**进程内库**，无子进程/二进制/JSON 管线，故不纳入（OUT），[错误处理](/sdk/errors#cli-error-family-out) |
| Hook types | 🟠 | 确定性治理层，整只子系统已成规范，占位，[Hooks](/sdk/hooks) |
| `OutputFormat` / `ThinkingConfig` / `EffortLevel` | 🟠 | 结构化输出对库调用尤其有用；thinking/effort 是现代 agent 控制面，多归 `llm_settings`，占位 |
| `SettingSource` / setting_sources | 🟠 | 是否加载 user/project/local 设置（含项目内存文件）；传空 = hermetic，利于 CI，占位 |
| `ToolsPreset` | ⚪ | 该预设的工具宇宙与 Brainary 不同，不移植（OUT） |
| `SdkBeta` | ⚪ | 已退役，仅登记（OUT） |
| `Transport`（自定义传输） | ⚪ | CLI 子进程逃生口；Brainary 内部自持传输，不作公共旋钮 |
| `StreamEvent`（partial 消息） | 🟡 | 归 token 级流式——现为步级，类型面待上游 |
| `RateLimitEvent` / `RateLimitInfo` | 🟠 | 面向托管模型的 agent SDK 应暴露限流状态以便退避，占位 |
| 后台任务消息（`TaskStarted` / `TaskProgress` / `TaskNotification` + `TaskUsage`） | 🟠 | 随 `stop_task`；v1 无后台任务模型 |
| `SandboxSettings` 家族 | 🟠 | 宿主内**命令沙箱**：约束 bash 工具的文件/命令/网络，占位。与 PoA/wasm 隔离整只 `.poa` 是不同概念，两者都要 |
| `SdkPluginConfig` / plugins | 🟠 | SDK **程序化**加载本地插件包（commands/agents/mcp），占位 |

### 内置工具与授权

| 接口 | 决策 | 一句理由 / 去处 |
| --- | --- | --- |
| **内置工具目录**（Read/Write/Edit/Bash/Glob/Grep/WebFetch/WebSearch/Agent 等，Brainary 原生名） | 🟢/🟠 | 编码智能体 SDK 的定义性面：文件类 🟢（`FolderPrimitive` 已供，schema 待精化 🟠），shell/web/交互/任务/子 agent 🟠，[内置工具目录](/sdk/builtin-tools) |
| `allowed_tools` / `disallowed_tools` | 🟠 | 声明式授权清单（可用性 ≠ 授权），占位，[权限模型](/sdk/permissions) |
| `permission_mode`（6 模）/ `CanUseTool` / `PermissionResult` | 🟠 | 控制面三件套，占位，指向已改写为完整规范的 [权限模型](/sdk/permissions) |

### 运行时控制（客户端方法）

| 接口 | 决策 | 一句理由 / 去处 |
| --- | --- | --- |
| `connect` / `query` / `interrupt` / `disconnect` | ✅ | 已实现，[两个入口](/sdk/query-and-client#full-method-face) |
| `set_model` / `set_permission_mode` / `rewind_files` | 🟠 | 运行时切换/文件检查点未做 |
| `get_mcp_status` / `reconnect_mcp_server` / `toggle_mcp_server` | 🟠 | MCP 运行时控制未做，v1 仅装配期挂载 |
| `stop_task` | 🟠 | 无后台任务模型 |
| `get_server_info` | 🟡 | 部分由 `system_prompt()` / `context_window()` getter 覆盖 |

> **Brainary 独有**：`step_once` / `revert`（手动单步回退）、`export_transcript`（只读快照）、`approx_context_tokens` / `context_window`（上下文检视）——均 ✅ 已实现，见 [两个入口](/sdk/query-and-client#brainaryclient-透传方法)。

## 相关

- [消息模型](/sdk/messages) —— 逐字段 v1 填充度对照表 · [成本字段](/sdk/messages#cost)
- [会话管理](/sdk/sessions) · [权限模型](/sdk/permissions) · [错误处理](/sdk/errors) —— 三个占位/新增面
- [中断、护栏与上下文](/sdk/interrupt-and-guardrails) —— 步边界中断、`max_turns`、溢出护栏、`auto_compact` 占位
- [会话导出](/sdk/transcript) —— 只导出、不可续跑（跨进程 resume 待上游）
