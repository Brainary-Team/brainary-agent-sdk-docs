---
outline: 2
---

# Hooks 生命周期钩子（架构已规划）

> **读完本页你能**：理解 hooks 是**包裹 agent 循环的确定性、代码驱动治理层**——在固定生命周期点触发，可观察 / 改写 / 拦截；掌握 Brainary Python 目标规格里的 `HookEvent` / `HookMatcher` / `HookCallback` / `HookContext` / `HookInput` / `HookJSONOutput` 六件套签名；看懂 `PreToolUse` 的 `permissionDecision` 与逐次授权回调 `can_use_tool` 如何组成「权限桥」。

::: warning 规划：Python 接口面（镜像 Rust）
Hooks 子系统为目标规格、尚未实现。Rust 侧见 [Rust：Hooks](/sdk/hooks)。
:::

**状态说明**：brainary-agent-sdk 当前**全部接口均为 🟠【规划中，未完成】**——架构已规划、尚未实现；下方给出的类型、签名、字段均为**已承诺的形态**，供对齐讨论，非占位草案。（⚪ = 暂缓 / 不纳入，非交付接口。）

::: warning 整个 Hooks 子系统为「架构已规划、尚未实现」（🟠）
下面的类型与签名是**目标规格**：定义「一个编码 agent SDK 的钩子面 *应当* 长什么样」，用来牵引仍在演进的底层架构。它们**不是**当前实现的映射，当前 `Options` 里没有 `hooks`。签名均为**已承诺的形状**（committed signatures），供与底层对齐时定稿——不是「签名待定」。
:::

## 为什么需要 hooks：确定性治理层

agent 循环里其实有两套「决策」在跑，务必分清：

- **LLM 自己发起的工具调用**：模型在推理中决定「我要调 `Bash` 跑这条命令」——这是**概率性**的，取决于提示词、上下文、模型当下的判断，你无法保证它每次都对。
- **hooks**：由**你的代码**在固定生命周期点（工具调用前后、用户提交提示、子 agent 起停、压缩前……）**确定性**地触发。它不参与模型推理，而是**包裹**着推理循环，在每个卡点上观察、改写、或直接拦截。

换句话说：LLM 的工具调用是 agent「想做什么」，hooks 是宿主「允许 / 记录 / 篡改它做什么」。这是一层**代码驱动的护栏**，行为可预测、可测试、可审计。

> **明确指引**：若要对**每一次**工具调用都设卡（gate every tool call），应当用 `PreToolUse` **hook**，而不是只依赖逐次权限回调 `can_use_tool`。权限回调面向「这一次调用允不允许」的裁决；`PreToolUse` hook 则是全量、无遗漏地拦在所有工具调用之前的确定性关口。两者可叠加，见下文[权限桥](#hooks-权限桥)。

## HookEvent：Brainary 目标事件集

`HookEvent` 是一个 `Literal`，枚举 agent 循环里可挂钩的生命周期点。Brainary 首版提供 **10 个事件**（其余更外围的事件仅登记）：

```python
HookEvent = Literal[
    "PreToolUse",           # 工具执行之前
    "PostToolUse",          # 工具成功之后
    "PostToolUseFailure",   # 工具失败之后
    "UserPromptSubmit",     # 用户提交提示时
    "Stop",                 # 主循环停止
    "SubagentStop",         # 子 agent 停止
    "SubagentStart",        # 子 agent 启动
    "PreCompact",           # 上下文压缩之前
    "Notification",         # 通知类事件
    "PermissionRequest",    # 需要一次权限裁决时
]
```

| 事件 | 触发时机 | 状态 |
| --- | --- | --- |
| `PreToolUse` | 工具执行**之前**——可改写入参 / 裁决放行拦截 | 🟠 |
| `PostToolUse` | 工具执行**成功之后**——可审计、可改写工具输出 | 🟠 |
| `PostToolUseFailure` | 工具执行**失败之后**——拿到 `error`、可回灌上下文 | 🟠 |
| `UserPromptSubmit` | 用户提交一条提示时——可注入 `additionalContext` | 🟠 |
| `Stop` | 主循环停止时 | 🟠 |
| `SubagentStop` | 子 agent 停止时 | 🟠 |
| `SubagentStart` | 子 agent 启动时 | 🟠 |
| `PreCompact` | 上下文**压缩之前**——随 core 压缩落地（M6） | 🟠 |
| `Notification` | 通知类事件（如需要用户关注） | 🟠 |
| `PermissionRequest` | 需要一次权限裁决时——可编程化处理，见[权限桥](#hooks-权限桥) | 🟠 |

> `PreCompact` 依赖 core 的**压缩**能力，随 M6 落地（自动压缩由 core 拥有，见 [边界与路线图](/sdk-py/limits)）。在压缩落地前，该事件永不触发。

**暂不纳入（⚪ 仅登记）**：`SessionStart` / `SessionEnd` / `Setup`（以及 `TeammateIdle` / `TaskCompleted` / `ConfigChange` / `WorktreeCreate` / `WorktreeRemove` / `PostToolBatch` / `MessageDisplay`）——它们更外围，Brainary 首版暂不纳入，仅在此登记以免遗漏。

## HookMatcher / HookCallback / HookContext

### HookMatcher — 匹配器 + 逐匹配器超时

一个 `HookMatcher` 把「匹配哪些工具」和「跑哪些回调」绑在一起。`matcher` 是工具名或竖线分隔的模式（如 `"Bash"`、`"Write|Edit"`）；`matcher=None` 表示**匹配全部工具**。`timeout` 是该匹配器下所有回调的整体超时（单位秒，默认 60）。

```python
from dataclasses import dataclass, field

@dataclass
class HookMatcher:
    matcher: str | None = None          # 工具名或模式，如 "Bash"、"Write|Edit"；None = 全部工具
    hooks: list[HookCallback] = field(default_factory=list)   # 命中时按序执行的回调
    timeout: float | None = None        # 本匹配器下所有回调的整体超时（秒），默认 60
```

### HookCallback — 回调签名

回调是一个 async 函数，拿到强类型 `HookInput`、可选的 `tool_use_id`、以及 `HookContext`，返回 `HookJSONOutput`。承诺签名：

```python
from typing import Callable, Awaitable

HookCallback = Callable[[HookInput, str | None, HookContext], Awaitable[HookJSONOutput]]
```

- `input`：按 `hook_event_name` 判别的强类型输入（见 [`HookInput`](#hookinput-按事件名判别的联合体)）
- `tool_use_id`：工具相关事件才有的本次工具调用标识
- `context`：附带旁路信息的 `HookContext`

### HookContext — 上下文

`HookContext` 携带回调运行时的旁路信息。首版只固定一个中止信号位（对齐后续步内取消能力）：

```python
from typing import Any
from typing_extensions import TypedDict

class HookContext(TypedDict):
    signal: Any | None   # 预留：中止信号支持（对齐 SDK 的 abort/interrupt）
```

## HookInput：按事件名判别的联合体

`HookInput` 是一个**判别联合**（discriminated union），判别键为 `hook_event_name`。所有变体都继承一组公共基字段：

```python
from typing import Any
from typing_extensions import Literal, NotRequired, TypedDict

class BaseHookInput(TypedDict):
    session_id: str
    transcript_path: str
    cwd: str
    permission_mode: NotRequired[str]

HookInput = (
    PreToolUseHookInput
    | PostToolUseHookInput
    | PostToolUseFailureHookInput
    | UserPromptSubmitHookInput
    | StopHookInput
    | SubagentStopHookInput
    | SubagentStartHookInput
    | PreCompactHookInput
    | NotificationHookInput
    | PermissionRequestHookInput
)
```

至少这三个 tool/prompt 相关变体的载荷字段需固定：

```python
class PreToolUseHookInput(BaseHookInput):
    hook_event_name: Literal["PreToolUse"]
    tool_name: str
    tool_input: dict[str, Any]
    tool_use_id: str
    agent_id: NotRequired[str]      # 在子 agent 内触发时有值
    agent_type: NotRequired[str]

class PostToolUseHookInput(BaseHookInput):
    hook_event_name: Literal["PostToolUse"]
    tool_name: str
    tool_input: dict[str, Any]
    tool_response: Any              # 工具执行的返回
    tool_use_id: str
    agent_id: NotRequired[str]
    agent_type: NotRequired[str]

class UserPromptSubmitHookInput(BaseHookInput):
    hook_event_name: Literal["UserPromptSubmit"]
    prompt: str
```

> `PostToolUseFailureHookInput` 额外带 `error: str`、`is_interrupt: NotRequired[bool]`；`PreCompactHookInput` 带 `trigger: Literal["manual", "auto"]` 与 `custom_instructions: str | None`；`PermissionRequestHookInput` 带 `tool_name` / `tool_input` / `permission_suggestions`。逐变体全表见对齐底稿。

## HookJSONOutput：裁决与执行面

这是 hooks 的**承重部分**——回调靠返回值来放行、拦截、注入消息、改写输入输出。它是控制字段 + 裁决字段 + 逐事件专属输出（`hookSpecificOutput`）的组合：

```python
class SyncHookJSONOutput(TypedDict):
    # —— 控制字段 ——
    continue_: NotRequired[bool]        # 是否继续（默认 True）；发往 CLI 时自动转为 continue
    stopReason: NotRequired[str]        # continue 为 False 时的停止原因
    suppressOutput: NotRequired[bool]   # 从记录里隐藏本 hook 的 stdout

    # —— 裁决字段 ——
    decision: NotRequired[Literal["block"]]   # "block" 拦截本次动作
    systemMessage: NotRequired[str]           # 展示给用户的告警消息
    reason: NotRequired[str]                  # 回灌给模型的反馈理由

    # —— 逐事件专属输出 ——
    hookSpecificOutput: NotRequired[HookSpecificOutput]

# 另有异步形态：延后执行
class AsyncHookJSONOutput(TypedDict):
    async_: Literal[True]               # 置 True 表示延后执行；发往 CLI 时自动转为 async
    asyncTimeout: NotRequired[int]      # 超时（毫秒）

HookJSONOutput = AsyncHookJSONOutput | SyncHookJSONOutput
```

> Python 里字段名带下划线（`continue_` / `async_`）以避开关键字，发往底层时自动转为 `continue` / `async`。

**`HookSpecificOutput`** 是按 `hookEventName` 判别的专属输出。两个承重变体：`PreToolUse` 携带**权限裁决** `permissionDecision`，`UserPromptSubmit` 携带**上下文注入** `additionalContext`：

```python
class PreToolUseHookSpecificOutput(TypedDict):
    hookEventName: Literal["PreToolUse"]
    # allow=直接放行；deny=拦截；ask=转人工追问；defer=交回默认权限流程
    permissionDecision: NotRequired[Literal["allow", "deny", "ask", "defer"]]
    permissionDecisionReason: NotRequired[str]
    updatedInput: NotRequired[dict[str, Any]]      # 放行但改写入参
    additionalContext: NotRequired[str]

class PostToolUseHookSpecificOutput(TypedDict):
    hookEventName: Literal["PostToolUse"]
    additionalContext: NotRequired[str]
    updatedToolOutput: NotRequired[Any]            # 改写工具输出

class UserPromptSubmitHookSpecificOutput(TypedDict):
    hookEventName: Literal["UserPromptSubmit"]
    additionalContext: NotRequired[str]            # 向模型注入额外上下文

class PermissionRequestHookSpecificOutput(TypedDict):
    hookEventName: Literal["PermissionRequest"]
    decision: dict[str, Any]                       # 直接给出权限决定

HookSpecificOutput = (
    PreToolUseHookSpecificOutput
    | PostToolUseHookSpecificOutput
    | UserPromptSubmitHookSpecificOutput
    | PermissionRequestHookSpecificOutput
)
```

> `permissionDecision` 的四态是权限桥的核心：`allow` 直接放行、`deny` 就地拦截、`ask` 升级为人工追问、`defer` 把决定权交回默认权限流程（即 `can_use_tool` 回调 / `permission_mode`）。详见[下文](#hooks-权限桥)。

## 配置：hooks 怎么挂进 Options

hooks 通过 `Options` 挂载，是一个键为 `HookEvent`、值为 `HookMatcher` 列表的字典（同一事件可挂多个匹配器，按序执行）。页面级见 [Options 统一配置](/sdk-py/options)。

```python
from brainary_agent_sdk import Options, HookMatcher

options = Options(
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[validate_bash], timeout=120),  # 仅 Bash，2 分钟超时
            HookMatcher(hooks=[audit_log]),                                   # 全部工具，默认 60s
        ],
        "PostToolUse": [HookMatcher(hooks=[audit_log])],
    },
)
```

## 范式示例

### (a) PreToolUse：拦截危险 bash 命令

命中 `Bash` 工具、命令里含 `rm -rf /` 时，返回 `permissionDecision: "deny"` 就地拦截：

```python
from typing import Any
from brainary_agent_sdk import HookContext

async def validate_bash(
    input_data: HookInput, tool_use_id: str | None, context: HookContext
) -> HookJSONOutput:
    """校验并拦截危险 bash 命令。"""
    if input_data.get("tool_name") == "Bash":
        command = input_data.get("tool_input", {}).get("command", "")
        if "rm -rf /" in command:
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "危险命令已拦截",
                }
            }
    return {}   # 默认放行（返回空即透传）
```

### (b) PostToolUse：审计日志

对**所有**工具（`matcher=None`）在执行后记一条审计日志，不改变行为：

```python
async def audit_log(
    input_data: HookInput, tool_use_id: str | None, context: HookContext
) -> HookJSONOutput:
    """审计所有工具调用。"""
    print(f"[audit] 工具已执行：{input_data.get('tool_name')}")
    return {}
```

挂上后即可正常发起查询，hooks 会在对应生命周期点自动触发：

```python
from brainary_agent_sdk import query

async for message in query(prompt="分析这个代码库", options=options):
    print(message)
```

## Hooks ↔ 权限桥 {#hooks-权限桥}

hooks 与[权限模型](/sdk-py/permissions)在「谁能调工具」上交汇，三条通路要分清：

- **`PreToolUse` 的 `permissionDecision`**：hook 在工具调用前直接给四态裁决。`allow` / `deny` 就地定案；`ask` 升级为人工追问；`defer`**把决定权交回默认权限流程**——也就是逐次授权回调 `can_use_tool` 与全局档位 `permission_mode`（见 [权限模型](/sdk-py/permissions)）。这让「代码规则先过一遍、拿不准的再落到权限回调」成为自然的两级结构。
- **`can_use_tool` 回调**：面向「**这一次**调用允不允许」的逐次裁决，看得到工具名与入参、可返回 `PermissionResultAllow`/`PermissionResultDeny`（可带理由或改写入参）。与 `PreToolUse` hook 的区别是：hook 是**全量、无遗漏**的确定性关口（推荐用它 gate 每次调用），回调是**逐次、可交互**的授权点。二者叠加：hook 先筛，`defer` 的落到回调。
- **`PermissionRequest` hook**：当需要一次权限裁决时触发，让你**编程化**地处理权限决定（返回 `PermissionRequestHookSpecificOutput` 的 `decision`），而非只靠交互式追问。它也承接沙箱回退——当模型请求越出沙箱执行（在工具入参里置 `dangerouslyDisableSandbox=True`）时，请求会回退到权限系统，由你的 `can_use_tool` 授权逻辑裁决。

**`decision_reason` 的流动**：`PreToolUse` 的 `permissionDecisionReason`（以及回调 `Deny` 的 `message`）会流入权限上下文并回灌给模型，让模型知道「为什么被拦」、据此调整下一步——拦截不是黑箱，而是带反馈的护栏。

## 相关

- [权限模型](/sdk-py/permissions) —— `permission_mode` / `can_use_tool` / `PermissionResult` 三件套
- [内置工具目录](/sdk-py/builtin-tools) —— hook 的 `matcher` 匹配的工具名从何而来
- [自定义工具 FunctionTools](/sdk-py/tools) —— 工具怎么装进 agent
- [边界与路线图](/sdk-py/limits) —— 覆盖矩阵与里程碑（含 M6 压缩 / `PreCompact`）
