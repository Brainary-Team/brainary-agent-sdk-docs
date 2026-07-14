---
outline: 2
---

# 接口索引（Python）

> **读完本页你能**：按 **Functions / Classes / Types** 分组,一眼查到每个接口的规划状态与文档落点。

这是一张**按接口名反查文档位置**的索引,按 Functions / Classes / Types 分组。它与本章另两张表**职责不同、互不重复**:

- [总览的接口一览](/sdk-py/overview#interface-overview) —— 接口的**命名与状态**;
- [边界的覆盖矩阵](/sdk-py/limits#coverage-matrix) —— 每个接口的**裁剪决策与理由**;
- **本页** —— Brainary 接口名 → **文档落点**(开发者查阅用)。

::: warning 本章整体是「规划：镜像 Rust 的 Python 接口面」
下表状态标记统一为 🟠【规划中，未完成】；Rust 与 Python 两侧当前均尚未实现,签名为设计形态。详见 [总览](/sdk-py/overview) 规划横幅。
:::

**状态说明**：brainary-agent-sdk 当前**全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；下方给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非占位草案。（⚪ = 暂缓 / 不纳入，非交付接口。）

## Functions

| 接口 | 状态 | 一句话 | 去哪页 |
| --- | --- | --- | --- |
| `query(prompt, options)` | 🟠 | 一次性入口,直接是 `AsyncIterator[Message]`,`async for` 消费 | [两个入口](/sdk-py/query-and-client#query-一次性) |
| `@tool(name, desc, schema)` | 🟠 | 把一个 async 函数标成工具 | [自定义工具](/sdk-py/tools#tool-装饰器) |
| `create_sdk_mcp_server(name, version, tools)` | 🟠 | 一组工具打包成命名能力单元 | [自定义工具](/sdk-py/tools#create-sdk-mcp-server) |
| **内置工具目录**（`read_file` / `write_file` / `edit_file` / `find_file` / `grep` 等） | 🟠（含 schema 精化缺口） | 随会话默认可用的一组内建工具；`bash` / `web_fetch` / `web_search` / `ask_user_question` / `agent`(🟠) 亦在此登记 | [内置工具目录](/sdk-py/builtin-tools) |
| `list_sessions()` | 🟠 | 列举跨进程历史会话（返回形态已定,签名已定） | [会话管理](/sdk-py/sessions#list-sessions) |
| `get_session_messages(session_id)` | 🟠 | 取某会话的消息（返回 `TranscriptMessage` 列表,形态已定） | [会话管理](/sdk-py/sessions#get-session-messages) |
| `get_session_info(session_id)` | 🟠 | 取某会话的元信息（返回 `SessionInfo`,形态已定） | [会话管理](/sdk-py/sessions#get-session-info) |
| `rename_session(session_id, title)` | 🟠 | 重命名会话（签名已定） | [会话管理](/sdk-py/sessions#rename-session) |
| `tag_session(session_id, tag)` | ⚪ | 打标签,暂缓 | [会话管理](/sdk-py/sessions) |

## Classes

| 接口 | 状态 | 一句话 | 去哪页 |
| --- | --- | --- | --- |
| `BrainaryClient` | 🟠 | 有状态多轮客户端；`async with` + `query` / `receive_response` / `await interrupt()` 及只读检视方法 | [两个入口](/sdk-py/query-and-client#brainaryclient-只读检视与单步) |

## Types

| 接口 | 状态 | 一句话 | 去哪页 |
| --- | --- | --- | --- |
| `Options`（dataclass) | 🟠 | 唯一配置对象,所有行为收敛于此 | [Options](/sdk-py/options#字段逐项) |
| `ModelSelection` | 🟠 | 模型接入信息（`Options.model_from_env()` / 显式构造) | [Options](/sdk-py/options) |
| `SystemPrompt` | 🟠 | 系统提示三来源（Default / Inline / TemplateFile) | [Options](/sdk-py/options#系统提示-systemprompt) |
| `Message`（union) | 🟠 | 流的元素,用 `isinstance` 判型 | [消息模型](/sdk-py/messages#四类消息) |
| `AssistantMessage` / `UserMessage` / `SystemMessage` / `ResultMessage` | 🟠 | 四类消息（`UserMessage` 待上游填充) | [消息模型](/sdk-py/messages#四类消息) |
| `ContentBlock`（union) | 🟠 | 内容块：`TextBlock`(🟠) / `ToolUseBlock` / `ToolResultBlock` / `ThinkingBlock`(🟠 类型就位不填充) | [消息模型](/sdk-py/messages#content-block) |
| `stop_reason`（4 取值) | 🟠 | 终局原因（stopped / max_turns / interrupted / context_exhausted) | [消息模型](/sdk-py/messages#stopreason) |
| `Usage` / `ResultMessage.total_cost_usd` | 🟠 | 成本面,类型就位、值恒 `None` 待上游 | [成本](/sdk-py/messages#cost) |
| `SdkMcpTool` / `CapabilityUnit` | 🟠 | `@tool` 产物 / `create_sdk_mcp_server()` 产物 | [自定义工具](/sdk-py/tools) |
| `SessionTranscript` / `TranscriptMessage` | 🟠 | 只读会话快照（`export_transcript()`,不可续跑) | [两个入口](/sdk-py/query-and-client#brainaryclient-只读检视与单步) |
| `SessionInfo` / `SessionMessage` | 🟠 | 会话元信息 / 会话消息（形态已定) | [会话管理](/sdk-py/sessions#返回类型-sessioninfo-完整字段集) |
| `PermissionMode`（6 模） / `CanUseTool` / `ToolPermissionContext` / `PermissionResultAllow` / `PermissionResultDeny` / `PermissionUpdate` / `PermissionRuleValue` | 🟠 | 权限控制面全套：模式枚举（default / acceptEdits / bypassPermissions / plan / … 6 态）、回调、上下文、允/拒判定结果、运行时增量更新与规则值 | [权限模型](/sdk-py/permissions) |
| `allowed_tools` / `disallowed_tools` | 🟠 | 工具准入白/黑名单（`Options` 字段,与权限判定联动) | [权限模型](/sdk-py/permissions) |
| `agents` / `AgentDefinition` | 🟠 | SDK 直挂子代理（在 `Options` 内声明式定义） | [Options](/sdk-py/options) · 子代理 |
| `setting_sources` / `add_dirs` / `sandbox` / `plugins` / `output_format` / `thinking` / `effort` / `fallback_model` | 🟠 | `Options` 配置旋钮：设置来源、附加工作目录、沙箱、插件、输出格式、思考开关、努力档位、回退模型 | [Options](/sdk-py/options) |
| `HookEvent` / `HookMatcher` / `HookCallback` / `HookInput` / `HookJSONOutput` | 🟠 | Hooks 子系统五件套：事件枚举、匹配器、回调、输入、结构化输出 | [Hooks](/sdk-py/hooks) |
| `AssistantMessageError` | 🟠 | 助手消息内的错误块（类型就位） | [消息模型](/sdk-py/messages) |
| `RateLimitEvent` / `RateLimitInfo` | 🟠 | 限流事件与配额信息（形态已定,未透出） | [消息模型](/sdk-py/messages) |
| `ToolAnnotations` | 🟠 | 工具行为提示（占位) | [自定义工具](/sdk-py/tools#toolannotations-工具行为提示-架构占位) |
| `McpServerConfig` 家族（Stdio / SSE / Http + 鉴权 `headers`） | 🟠 | MCP server 富配置：三种传输 + 鉴权头（糖仍可只收 URL） | MCP 接入 |
| `BrainaryError` 异常类树（`BuildError` / `AuthenticationError` / `RateLimitError` / `ToolExecutionError` …） | 🟠 | 自解释命名的异常子类,`except 具体子类` 分支;`except BrainaryError` 兜底。不设 `CLI*Error` 一族 | [错误处理](/sdk-py/errors) |

> 上表已登记本轮新增的内置工具、Hooks、权限全套、`Options` 旋钮与消息新增类型。其余全表面（含 `Transport` / `StreamEvent` / 后台任务消息等尚未落地的接口)的**处置决策**见 [边界与路线图 · 覆盖矩阵](/sdk-py/limits#coverage-matrix)。

## 相关

- [能力总览](/sdk-py/overview) · [边界与路线图](/sdk-py/limits)
- 对照 Rust 版：[接口索引](/sdk/api-index)
