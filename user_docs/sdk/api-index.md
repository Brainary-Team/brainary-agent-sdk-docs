---
outline: 2
---

# 接口索引

> **读完本页你能**：按 **Functions / Classes / Types** 分组,一眼查到每个公开接口的实现状态与文档落点。

这是一张**按接口名反查文档位置**的索引,按 Functions / Classes / Types 分组。它与本章另两张表**职责不同、互不重复**:

- [总览的接口一览](/sdk/overview#interface-overview) —— 接口的**命名与状态**;
- [边界的覆盖矩阵](/sdk/limits#coverage-matrix) —— 每个接口的**裁剪决策与理由**;
- **本页** —— Brainary 接口名 → **文档落点**(开发者查阅用)。

**状态图例(全站统一 4 态)**：🟢 已实现 · 🟡 类型/旋钮就位待上游 · 🟠 架构已规划未实现 · ⚪ 暂缓/仅登记

## Functions

| 接口 | 状态 | 一句话 | 去哪页 |
| --- | --- | --- | --- |
| `query(prompt, options)` | 🟢 | 一次性入口,返回 `'static` 的 `MessageStream` | [两个入口](/sdk/query-and-client#query-一次性) |
| `#[tool]`（宏） | 🟢 | 把一个类型标成工具 | [自定义工具](/sdk/tools#核心-api) |
| `FunctionTools::new(name, desc)` | 🟢 | 一组工具打包成命名能力单元 | [自定义工具](/sdk/tools#核心-api) |
| **内置工具目录**（`read_file` / `write_file` / `edit_file` / `find_file` / `grep` 等） | 🟢（schema 精化 🟠) | 随会话默认可用的一组内建工具；`bash` / `web_fetch` / `web_search` / `ask_user_question` / `agent`(🟠) 亦在此登记 | [内置工具目录](/sdk/builtin-tools) |
| `list_sessions()` | 🟠 | 列举跨进程历史会话（返回形态已定,签名已定） | [会话管理](/sdk/sessions) |
| `get_session_messages(id)` | 🟠 | 取某会话的消息（返回 `TranscriptMessage` 列表,形态已定） | [会话管理](/sdk/sessions) |
| `get_session_info(id)` | 🟠 | 取某会话的元信息（返回 `SessionInfo`,形态已定） | [会话管理](/sdk/sessions) |
| `rename_session(id, name)` | 🟠 | 重命名会话（签名已定） | [会话管理](/sdk/sessions) |
| `tag_session(id, tag)` | ⚪ | 打标签,暂缓 | [会话管理](/sdk/sessions) |

## Classes

| 接口 | 状态 | 一句话 | 去哪页 |
| --- | --- | --- | --- |
| `BrainaryClient` | 🟢 | 有状态多轮客户端；`connect` / `query` / `receive_response` / `interrupt_handle` 等透传方法 | [两个入口](/sdk/query-and-client#brainaryclient-透传方法) |
| `PoaRunner`（`poa` feature） | 🟢 | 第三个入口：库调用跑沙箱化 `.poa` 程序 | [运行一个 PoA](/sdk/running-a-poa) |

## Types

| 接口 | 状态 | 一句话 | 去哪页 |
| --- | --- | --- | --- |
| `Options`（`Options::builder()`) | 🟢 | 唯一配置对象,所有行为收敛于此 | [Options](/sdk/options) |
| `ModelSelection` | 🟢 | 模型接入信息（`from_env()` / 显式构造) | [Options](/sdk/options#选模型-modelselection) |
| `SystemPrompt` | 🟢 | 系统提示三来源（Default / Inline / TemplateFile) | [Options](/sdk/options#系统提示-systemprompt) |
| `Message`（enum) | 🟢 | 流的元素：Assistant / User / System / Result | [消息模型](/sdk/messages#四类消息) |
| `AssistantMessage` / `UserMessage` / `SystemMessage` / `ResultMessage` | 🟢/🟡 | 四类消息（`UserMessage` 待上游填充) | [消息模型](/sdk/messages#四类消息) |
| `ContentBlock`（enum) | 🟢/🟡 | 内容块：`Text`(🟢) / `ToolUse` / `ToolResult` / `Thinking`(🟡 类型就位不填充) | [消息模型](/sdk/messages#content-block) |
| `StopReason` | 🟢 | 终局原因四变体（Stopped / MaxTurns / Interrupted / ContextExhausted) | [消息模型](/sdk/messages#stopreason-四变体) |
| `Usage` / `ResultMessage.total_cost_usd` | 🟡 | 成本面,类型就位、值恒 `None` 待上游 | [成本](/sdk/messages#cost) |
| `InterruptHandle` | 🟢 | 中断句柄（`interrupt()` / `is_interrupted()`) | [中断与护栏](/sdk/interrupt-and-guardrails#步间协作式中断) |
| `SessionTranscript` / `TranscriptMessage` | 🟢 | 只读会话快照（可序列化,不可续跑) | [会话导出](/sdk/transcript#核心-api) |
| `SessionInfo` | 🟠 | 会话元信息（形态已定) | [会话管理](/sdk/sessions) |
| `PermissionMode`（6 模） / `CanUseTool` / `ToolPermissionContext` / `PermissionResult` / `PermissionUpdate` / `PermissionRuleValue` | 🟠 | 权限控制面全套：模式枚举（default / accept_edits / bypass_permissions / plan / … 6 态）、回调、上下文、判定结果、运行时增量更新与规则值 | [权限模型](/sdk/permissions) |
| `allowed_tools` / `disallowed_tools` | 🟠 | 工具准入白/黑名单（`Options` 字段,与权限判定联动) | [权限模型](/sdk/permissions) |
| `agents` / `AgentDefinition` | 🟠 | SDK 直挂子代理（在 `Options` 内声明式定义） | [Options](/sdk/options) · 子代理 |
| `setting_sources` / `add_dirs` / `sandbox` / `plugins` / `output_format` / `thinking` / `effort` / `fallback_model` | 🟠 | `Options` 配置旋钮：设置来源、附加工作目录、沙箱、插件、输出格式、思考开关、努力档位、回退模型 | [Options](/sdk/options) |
| `HookEvent` / `HookMatcher` / `HookCallback` / `HookInput` / `HookJSONOutput` | 🟠 | Hooks 子系统五件套：事件枚举、匹配器、回调、输入、结构化输出 | [Hooks](/sdk/hooks) |
| `AssistantMessageError` | 🟡 | 助手消息内的错误块（类型就位） | [消息模型](/sdk/messages) |
| `RateLimitEvent` / `RateLimitInfo` | 🟠 | 限流事件与配额信息（形态已定,未透出） | [消息模型](/sdk/messages) |
| `ToolAnnotations` | 🟠 | 工具行为提示（占位) | [自定义工具](/sdk/tools#toolannotations-工具行为提示-架构占位) |
| `McpServerConfig` 家族（Stdio / SSE / Http + 鉴权 `headers`） | 🟡 | MCP server 富配置：三种传输 + 鉴权头（糖仍可只收 URL） | MCP 接入 |
| `BrainaryError` / `ErrorCategory` | 🟡 / 🟠 | 一个 `#[non_exhaustive]` 枚举 + `category()` 可恢复性分类（家族目录在 core)；不含 `CLI*Error` 一族 | [错误处理](/sdk/errors) |
| `PoaOutcome` / `RunReport` | 🟢 | PoA 运行结果与报告（`poa` feature) | [运行一个 PoA](/sdk/running-a-poa#返回值-poaoutcome) |

> 上表已登记本轮新增的内置工具、Hooks、权限全套、`Options` 旋钮与消息新增类型。其余全表面（含 `Transport` / `StreamEvent` / 后台任务消息等尚未落地的接口)的**处置决策**见 [边界与路线图 · 覆盖矩阵](/sdk/limits#coverage-matrix)。

## 相关

- [能力总览](/sdk/overview) · [边界与路线图](/sdk/limits)
- 对照 Python 版：[接口索引](/sdk-py/api-index)
