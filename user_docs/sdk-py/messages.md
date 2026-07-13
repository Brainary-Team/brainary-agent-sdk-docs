---
outline: 2
---

# 消息模型（Python）

> **读完本页你能**：看懂异步流里的四类消息与四种内容块、`stop_reason` 的四个变体、错误如何走异常通道，以及成本字段的填充度。

::: warning 规划：Python 接口面（镜像 Rust）
下方类型为设计形态、尚未实现，见 [总览](/sdk-py/overview) 的规划横幅。Rust 侧的等价物见 [Rust：消息模型](/sdk/messages)。
:::

SDK 的消息模型是一个 `Message` union：**四类消息各是一个独立 dataclass，用 `isinstance()` 判型**（`AssistantMessage` / `ResultMessage` 等）。形状建齐（四类消息 × 四种内容块），但只填底层能给的，其余字段类型就位而不填充。

## 一条流长什么样

```python
from brainary_agent_sdk import query, Options
from brainary_agent_sdk import SystemMessage, AssistantMessage, ResultMessage, TextBlock

options = Options(model=Options.model_from_env())

async for msg in query(prompt="介绍一下你自己。", options=options):
    if isinstance(msg, SystemMessage):
        print("[system]", msg.subtype)              # 开头一条 init
    elif isinstance(msg, AssistantMessage):
        for block in msg.content:
            if isinstance(block, TextBlock):
                print(block.text)
    elif isinstance(msg, ResultMessage):
        print("停机：", msg.stop_reason, "共", msg.num_turns, "步")
```

预期序列：先一条 `SystemMessage(subtype="init")`，然后若干 `AssistantMessage`，最后一条 `ResultMessage` 收尾。

## 四类消息

流里的每一项是 `Message` union 的一个成员——**四类消息各是一个独立 dataclass，用 `isinstance()` 判型**（`AssistantMessage` / `ResultMessage` 等）：

```python
from dataclasses import dataclass

# Message = 流里可能出现的消息类型的联合（用 isinstance 判型，非枚举）
Message = SystemMessage | AssistantMessage | UserMessage | ResultMessage

@dataclass
class AssistantMessage:
    content: list[ContentBlock]                    # 本步的内容块序列；v1 只填 TextBlock
    requested_tools: bool = False                  # 本步是否请求了工具（v1 粗信号）
    model: str | None = None                       # 实际使用的模型名
    error: AssistantMessageError | None = None     # 结构化的单步失败类别（见下）

@dataclass
class UserMessage:
    content: list[ContentBlock]
    # 🟡 未来加 parent_tool_use_id / tool_use_result，见「UserMessage 未来字段」

@dataclass
class SystemMessage:
    subtype: str                                   # v1 每次运行开头一条 "init"
    data: dict                                     # init 携带 {"model": ...}

@dataclass
class ResultMessage:
    num_turns: int                                 # 本次运行累计步数
    stop_reason: str                               # 为何停机，见「stop_reason 四变体」
    approx_context_tokens: int | None = None       # 当前上下文近似 token 数
    usage: Usage | None = None                     # 🟡 恒 None，待上游（见「成本」）
    total_cost_usd: float | None = None            # 🟡 恒 None，待上游
    is_error: bool = False                         # 恒 False（错误走异常通道，不作停机原因）
    # 追加诊断字段（session_id / duration_ms …）见「ResultMessage 追加字段」
```

各类的 v1 填充行为：

| 类 | v1 行为 |
| --- | --- |
| `AssistantMessage` | 模型走一步；只填 `TextBlock`，`error` 类型就位不填充 |
| `UserMessage` | 类型就位，一般不填充（未来加两个字段，见[下文](#usermessage-未来字段)） |
| `SystemMessage` | 每次运行开头发一条 `subtype="init"` |
| `ResultMessage` | 一次运行的终局摘要；`usage` / `total_cost_usd` 恒 `None`（见[追加字段](#resultmessage-追加字段)） |

### AssistantMessage.error：结构化的单步失败类别 {#assistant-message-error}

`AssistantMessage.error`（🟡 类型就位待上游）给「这一步为什么失败」一个**可判定的类别**，让你不必去异常的字符串里做子串匹配。它是一个 optional literal：

```python
AssistantMessageError = Literal[
    "authentication_failed",   # 鉴权失败（API key 无效/过期）
    "billing_error",           # 账单问题（额度/欠费）
    "rate_limit",              # 触发限流，配合 RateLimitEvent 做退避
    "invalid_request",         # 请求本身非法
    "server_error",            # 上游 5xx
    "max_output_tokens",       # 单条回复触顶输出上限
    "unknown",                 # 其余归为未知的情况
]
# AssistantMessage.error: AssistantMessageError | None
```

**它与「迭代时抛 `BrainaryError`」的异常通道正交、互补而非替代**：

- 抛出的 `BrainaryError` 是**异常**——它终止流，决定「要不要继续」。
- `AssistantMessage.error` 是**这一步的失败分类标签**——它随一条未被抛掉的 `AssistantMessage` 一起到手，让你在**不解析字符串**的前提下按 `"rate_limit"` / `"authentication_failed"` / … 分支决策（例：`"rate_limit"` → 退避重试；`"authentication_failed"` → 提示重新登录）。

```python
elif isinstance(msg, AssistantMessage):
    if msg.error == "rate_limit":
        await back_off()
    elif msg.error == "authentication_failed":
        prompt_relogin()
    for block in msg.content:
        ...
```

`error` 为 `None` 表示这一步没有可归类的失败；它不改变「异常走 `async for` 抛出」这条主线。

## 内容块 ContentBlock {#content-block}

一条消息的 `content` 是一个 `list[ContentBlock]`——**块是消息的组成单位**，归在消息模型之下（故不单开一页）。每种块也是独立 dataclass：

```python
# ContentBlock = 一条消息 content 列表里可能出现的块类型的联合
ContentBlock = TextBlock | ToolUseBlock | ToolResultBlock | ThinkingBlock

@dataclass
class TextBlock:
    text: str                                # 🟢 文本

@dataclass
class ToolUseBlock:
    id: str                                  # 🟡 不填充：工具调用 id
    name: str                                # 被请求的工具名
    input: dict                              # 模型给该工具的入参

@dataclass
class ToolResultBlock:
    tool_use_id: str                         # 🟡 不填充：对应的 ToolUseBlock.id
    content: str | None = None               # 工具返回内容
    is_error: bool = False                   # 工具是否报错

@dataclass
class ThinkingBlock:
    thinking: str                            # 🟡 不填充：深度思考文本
    signature: str | None = None             # 思考签名（可选）
```

| 类 | 字段要点 | v1 |
| --- | --- | --- |
| `TextBlock` | `text: str` | 🟢 |
| `ToolUseBlock` | `id`, `name`, `input: dict` | 🟡 不填充 |
| `ToolResultBlock` | `tool_use_id`, `content`, `is_error` | 🟡 不填充 |
| `ThinkingBlock` | `thinking: str`, `signature` | 🟡 不填充 |

## 成本：total_cost_usd 与 usage {#cost}

`ResultMessage` 的两个成本字段**类型已就位、值待上游**：

| 字段 | 类型 | v1 | 上游后 |
| --- | --- | --- | --- |
| `total_cost_usd` | `float \| None` | 🟡 恒 `None` | 🟢 真实花费（美元） |
| `usage` | `Usage \| None` | 🟡 恒 `None` | 🟢 真实 token 计量 |

`Usage` 是 token 计量（dataclass）；v1 恒 `None`，上游后填真实值：

```python
@dataclass
class Usage:
    input_tokens: int | None = None                  # 输入 token 数
    output_tokens: int | None = None                 # 输出 token 数
    cache_creation_input_tokens: int | None = None   # 写缓存的输入 token
    cache_read_input_tokens: int | None = None        # 命中缓存的输入 token
```

> 成本的**配置侧**是 `Options.billing_cap`（预算上限），见 [Options](/sdk-py/options#字段逐项)。配置项进 `Options`、结果字段进 `ResultMessage`。

## ResultMessage 追加字段（登记规划） {#resultmessage-追加字段}

为补全结果消息的诊断面，`ResultMessage` 追加以下字段。它们随形状建齐、按依赖分状态填充：

| 字段 | 类型 | 状态 | 说明 |
| --- | --- | --- | --- |
| `session_id` | `str \| None` | 🟠 依赖会话面 | 会话面的 join key：把本次运行的 `ResultMessage` 关联回一个会话/transcript。会话面落地前恒 `None`。 |
| `duration_ms` | `int \| None` | 🟡 类型就位待上游 | 本次运行的墙钟耗时（毫秒）。 |
| `api_error_status` | `int \| None` | 🟡 配合 error 分类 | 终止性 API 错误的 HTTP 状态码；与 [`AssistantMessageError`](#assistant-message-error) 配套，让你既知类别又知状态码。无终止错误时 `None`。 |
| `permission_denials` | `list \| None` | 🟠 依赖权限面 | 本次运行被权限面拒绝的工具调用记录。权限面落地前恒 `None`。 |
| `errors` | `list[str] \| None` | 🟡 类型就位待上游 | 循环级错误字符串（如 max-turns 提示），用于诊断而非分支。 |

`is_error` 的语义不变——恒 `False`（错误走异常通道，不作停机原因）；要判断「这一步/这次为何失败」，请用结构化的 [`AssistantMessageError`](#assistant-message-error)（步级类别）与 `api_error_status`（HTTP 状态码），而非 `is_error` 布尔。

## RateLimitEvent / RateLimitInfo：限流状态流事件 {#rate-limit-event}

::: tip 状态：🟠 已规划（原为「不建模」）
限流状态原先仅登记为不建模；现改为架构已规划：作为一类**流事件**透出，让调用方能实现退避。类型形态先给出，v1 不透出。
:::

`RateLimitEvent` 在限流状态变化时进入消息流（如从 `"allowed"` 变为 `"allowed_warning"`），携带一份 `RateLimitInfo`：

```python
RateLimitStatus = Literal["allowed", "allowed_warning", "rejected"]

@dataclass
class RateLimitInfo:
    status: RateLimitStatus
    resets_at: int | None = None        # 窗口重置的 Unix 时间戳
    rate_limit_type: str | None = None
    utilization: float | None = None    # 已消耗比例 0.0..1.0
    # …其余 overage 字段

@dataclass
class RateLimitEvent:
    rate_limit_info: RateLimitInfo
    session_id: str
```

- `"allowed_warning"`：逼近上限——在撞到硬限前提前警示用户。
- `"rejected"`：已被限流——用 `resets_at` 决定退避多久后重试（配合 [`AssistantMessageError` 的 `"rate_limit"`](#assistant-message-error)）。

用 `isinstance(msg, RateLimitEvent)` 判型；v1 不透出，形状先就位。

## UserMessage 未来字段 {#usermessage-未来字段}

`UserMessage` 当前只有 `content`。待 subagent（子代理）与工具结果回填落地后，追加两个字段（🟡 类型就位、v1 不填充）：

| 字段 | 类型 | 用途 |
| --- | --- | --- |
| `parent_tool_use_id` | `str \| None` | 该用户轮由哪个工具调用触发（子代理嵌套时的父指针）。 |
| `tool_use_result` | `... \| None` | 承载工具执行结果，喂回下一步。 |

v1 不填充这两个字段；形状先建齐，subagent/工具结果面落地后按加法式填充。

## stop_reason 四变体 {#stopreason}

`ResultMessage.stop_reason` 说明为什么停：

| 值 | 含义 |
| --- | --- |
| `"stopped"` | 模型不再请求工具，正常完成 |
| `"max_turns"` | `max_turns` 护栏触顶 |
| `"interrupted"` | `client.interrupt()` 请求了步间中断 |
| `"context_exhausted"` | 上下文溢出护栏在下一步前触发 |

**没有 `"error"` 变体**——错误不是停机原因，它走异常通道（见下）。

## 错误模型：异常与终局 Result 正交

- **单步失败** → 迭代时抛 `BrainaryError`（`async for` 处抛出），流随即结束。
- **正常终局** → 一条 `ResultMessage`，`stop_reason` 说明原因。

所以你**永远不会**在 `ResultMessage` 里读到「出错了」的布尔——`is_error` 恒为 `False`。要按**原因**分支，用步级的 [`AssistantMessageError`](#assistant-message-error)（结构化类别）与 `ResultMessage.api_error_status`（HTTP 状态码），而非 `is_error`。完整接法见 [错误处理](/sdk-py/errors)。

## 相关

- [两个入口：消费消息流](/sdk-py/query-and-client) · [错误处理](/sdk-py/errors)
- 对照 Rust：[消息模型](/sdk/messages)
