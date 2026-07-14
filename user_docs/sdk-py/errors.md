---
outline: 2
---

# 错误处理（Python）

> **读完本页你能**：看懂 `BrainaryError` 异常**类层级**（`BuildError` / `RateLimitError` / `ToolExecutionError` …）、知道每个异常从哪来（构建期 vs 运行期）、会用 `except 具体子类` 按恢复策略分支，并知道哪些 CLI 子进程相关异常我们**故意不纳入**。

::: warning 规划：Python 接口面（镜像 Rust）
下方异常类层级为设计形态、尚未实现，见 [总览](/sdk-py/overview) 的规划横幅。它与 Rust 侧**同一个错误模型、各用本语言惯用法表达**——Rust 是一个 `#[non_exhaustive]` 枚举 + `category()` 访问器，Python 是一套**异常子类**。Rust 侧见 [错误处理](/sdk/errors) 与 类型与错误参考。
:::

Python 里错误类型的惯用做法是**用自解释的类名建一棵异常树**（一个基类 + 命名子类），这样 `except RateLimitError:` 一眼就知道在接什么，而不必 `except BrainaryError as e: if e.category() == ...`。所有异常都从 **`BrainaryError`** 派生——`except BrainaryError:` 仍能兜住全部。

## 异常类层级（一览）

```text
BrainaryError(Exception)          # 基类：except 它 = 兜住本 SDK 的一切错误
├── BuildError                    # 构建期（发任何模型请求之前）：配置/装配问题
│   ├── DuplicateToolError            # 两个工具同名
│   ├── DuplicateNamespaceError       # 两个命名空间撞名
│   ├── ReservedNamespaceError        # 命名空间用了保留字（如 "global"）
│   ├── TemplateError                 # 系统提示 Jinja2 模板语法/求值错
│   └── MissingMcpResourceError       # MCP 服务未暴露可解析的 brainary 资源
├── APIError                      # 运行期·模型/供应商侧失败（可据类别决定是否重试）
│   ├── AuthenticationError           # 鉴权失败 —— 修 key，别重试
│   ├── BillingError                  # 计费/额度 —— 停，报人
│   ├── RateLimitError                # 限流 —— 退避后重试（带 retry_after）
│   ├── InvalidRequestError           # 请求非法 —— 调用方配置/入参 bug
│   ├── ServerError                   # 供应商 5xx —— 可重试
│   ├── RequestTimeoutError           # 超时 —— 可重试
│   └── MaxTokensError                # 触顶 max_output_tokens —— 加预算/续跑
└── ToolExecutionError            # 运行期·某个工具自身抛错
```

> 命名与 Rust 的 `ErrorCategory` 一一对应（`RateLimitError` ⟷ `ErrorCategory::RateLimit`，`BuildError` ⟷ `Config` …）。同一恢复语义，两语言各用本地形态表达。

**状态**：基类 `BrainaryError` 🟠（镜像 Rust 现状）；`BuildError` 及其子类对应 Rust 侧规划的构建期领域变体（形态 🟠，Python 实现本身随本章 🟠）；`APIError` 家族 🟠（架构已规划，映射到步级 [`AssistantMessageError`](/sdk-py/messages#assistant-message-error) 的类别）；`ToolExecutionError` 🟠（类型就位，待上游把工具失败结构化）。

### 带数据字段的异常（签名） {#exception-fields}

多数异常只承载消息文本（从 `Exception` 继承）；下面几个额外带**结构化字段**，供恢复逻辑读取——签名已承诺（🟠）：

```python
class BrainaryError(Exception):
    """基类：所有 SDK 异常的根。except 它可兜住一切。"""

class RateLimitError(APIError):
    retry_after: float | None    # 建议退避秒数（供应商给出时）；None 表示未知，用默认退避

class ToolExecutionError(BrainaryError):
    tool_name: str               # 抛错的工具名
    tool_use_id: str | None      # 触发的 ToolUseBlock.id（可关联回消息流）
    message: str                 # 工具自身的错误描述
```

其余异常（`AuthenticationError` / `BillingError` / `DuplicateToolError` / …）不额外带字段，仅靠**类型本身**分支即可，`str(e)` 取人类可读描述。

## 错误从哪来：两个位置

| 位置 | 抛什么 | 什么时候 |
| --- | --- | --- |
| **构建期** | `BuildError` 的某个子类 | 构造 `Options` / `BrainaryClient` / 首次 `query()` 装配 agent 时——**发任何模型请求之前** |
| **运行期** | `APIError` 子类 或 `ToolExecutionError` | `async for` 消费消息流时：模型调用出错、工具抛错、MCP 故障等 |

两处都从 `BrainaryError` 派生，`except BrainaryError:` 可统一兜底。

## 运行期：按子类分支恢复策略

错误**不是**一种停机原因（`stop_reason` 里没有 `"error"`），而是在消费流时抛出。用**具体子类**分支，才能对不同失败采取不同动作：

```python
import asyncio
from brainary_agent_sdk import (
    query, Options, ResultMessage,
    BrainaryError, RateLimitError, AuthenticationError, ServerError,
)

options = Options(model=Options.model_from_env())

try:
    async for msg in query(prompt="介绍一下你自己。", options=options):
        if isinstance(msg, ResultMessage):
            print("正常停机：", msg.stop_reason)
except RateLimitError as e:
    await asyncio.sleep(e.retry_after or 5)   # 限流 —— 退避后重试
except (AuthenticationError,) as e:
    raise SystemExit(f"鉴权失败，请检查 key：{e}")   # 别重试
except ServerError as e:
    ...                                        # 供应商 5xx —— 可重试
except BrainaryError as e:
    print("其他运行错误：", e)                  # 兜底
```

> **正常终局 vs 出错是两条正交通道**：`ResultMessage` 是「跑完了，这是为什么停」；异常是「中途炸了」。所以你**永远不会**在 `ResultMessage` 里读到「出错了」的布尔——`is_error` 恒为 `False`。要按**原因**分支，用上面的异常子类或步级 [`AssistantMessageError`](/sdk-py/messages#assistant-message-error)。见 [消息模型](/sdk-py/messages#错误模型-异常与终局-result-正交)。

## 构建期：配置错误当场报 {#build-checks}

配置类问题在构造 / 装配 agent 时就抛 `BuildError` 子类，不拖到运行期。SDK 层最常撞到的：

| 异常子类 | 含义 | 怎么修 |
| --- | --- | --- |
| `DuplicateToolError` | 两个工具暴露了同名工具 | 改工具 `name` 保证全局唯一 |
| `DuplicateNamespaceError` | 两个命名空间撞名 | 改其一的 `name` |
| `ReservedNamespaceError` | 某能力单元命名为保留字（如 `global`） | 换个名字 |
| `TemplateError` | 系统提示 Jinja2 模板语法/求值错 | 检查 `system_prompt` |
| `MissingMcpResourceError` | MCP 服务未暴露可解析的 `brainary` 资源 | 见 MCP 接入 |

这些来自命名能力单元 / primitive 的**构建期校验**，见 [自定义工具](/sdk-py/tools#build-checks)。想一把接住所有配置问题，`except BuildError:` 即可。

## 不纳入的：`CLINotFoundError` / `ProcessError` 一族（OUT） {#cli-error-family-out}

有一类 SDK 会带 `CLINotFoundError` / `CLIConnectionError` / `ProcessError`(exit_code/stderr) / `CLIJSONDecodeError`(line) 这几个异常。**我们不纳入它们**——它们不是「更规范的错误设计」，而是 **shell-out 到某个 CLI 子进程**这类传输方式的副作用（找不到二进制、连不上子进程、子进程非零退出、解析不了子进程吐的 JSON 行）。

Brainary SDK 是**进程内库**（`query` / `BrainaryClient` 驱动宿主内 agent），没有子进程、二进制或 JSON 管线，照抄这一族等于把别人的传输事故当规格进口。处置详见 [边界与路线图 · 覆盖矩阵](/sdk-py/limits#coverage-matrix)。

## 完整目录与跨语言契约

异常类层级是**门面视图**；底层错误契约（变体、透传规则、`ErrorCategory` 分类）跨语言一致，权威目录在核心层：

- 类型与错误参考 —— `BrainaryError` 全变体 + `ErrorCategory` + 排错速查表

## 相关

- [消息模型](/sdk-py/messages#错误模型-异常与终局-result-正交) —— 异常与 `stop_reason` 正交、`AssistantMessageError` 类别
- [自定义工具](/sdk-py/tools#build-checks) —— 构建期校验
- [边界与路线图](/sdk-py/limits) —— `CLI*Error` 一族的 OUT 处置
- 对照 Rust：[错误处理](/sdk/errors)
