---
outline: 2
---

# 自定义工具（Python）

> **读完本页你能**：用 `@tool` 写一个工具，用 `create_sdk_mcp_server()` 把一组工具打包成命名能力单元，挂进 `Options`，并了解 MCP 与 ToolAnnotations 的规划位置。

::: warning 规划：Python 接口面（镜像 Rust）
下方签名为设计形态、尚未实现，见 [总览](/sdk-py/overview) 的规划横幅。Rust 侧的等价物见 [Rust：自定义工具](/sdk/tools)。
:::

## 概念简述

能力的打包单元叫 **primitive**。写完整 primitive 较繁琐；多数时候你只想「加几个函数当工具」。这条捷径是两件套：

- **`@tool`**：把一个 async 函数标成工具（= 一个工具）。
- **`create_sdk_mcp_server()`**：把一组 `@tool` 函数打包成一个命名能力单元（= namespace + 一组工具）。

## `@tool` 装饰器

被装饰的 async 函数收 `args: dict`、返回 `{"content": [...]}`：

```python
def tool(
    name: str,
    description: str,
    input_schema: type | dict[str, Any],
    annotations: ToolAnnotations | None = None,
) -> Callable[..., SdkMcpTool]:
    ...
```

**参数**

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `name` | `str` | 必填 | 工具唯一标识 |
| `description` | `str` | 必填 | 工具用途的人类可读描述 |
| `input_schema` | `type \| dict[str, Any]` | 必填 | 入参 schema：简单类型映射（`{"city": str}`，推荐）或完整 JSON Schema |
| `annotations` | `ToolAnnotations \| None` | `None` | 行为提示（🟠 占位，见下节） |

**返回**：一个装饰器，把工具实现包装成可挂载的工具单元。

```python
from brainary_agent_sdk import tool

@tool("get_weather", "查询城市当前天气", {"city": str})
async def get_weather(args: dict) -> dict:
    city = args["city"]
    return {"content": [{"type": "text", "text": f"{city} 天气晴"}]}
```

- `input_schema` 支持**简单类型映射**（`{"city": str}`，推荐）或完整 JSON Schema。
- 返回值是 `{"content": [...]}`——内容块列表形状。

## `create_sdk_mcp_server()` {#create-sdk-mcp-server}

把一组 `@tool` 函数打包成一个命名能力单元，挂进 `Options.extra_tools`：

```python
def create_sdk_mcp_server(
    name: str,
    version: str = "1.0.0",
    tools: list[SdkMcpTool] | None = None,
) -> CapabilityUnit:
    ...
```

**参数**

| 参数 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `name` | `str` | 必填 | 命名能力单元名 = 系统提示里的命名空间 |
| `version` | `str` | `"1.0.0"` | 版本串 |
| `tools` | `list[SdkMcpTool] \| None` | `None` | 一组 `@tool` 装饰的函数 |

**返回**：一个命名能力单元（对应 Rust `FunctionTools`），可挂进 `Options.extra_tools`。

```python
from brainary_agent_sdk import tool, create_sdk_mcp_server, Options

@tool("get_weather", "查询城市当前天气", {"city": str})
async def get_weather(args: dict) -> dict:
    return {"content": [{"type": "text", "text": f"{args['city']} 天气晴"}]}

# 一组工具 = 一个命名能力单元
weather = create_sdk_mcp_server(
    name="weather",              # 即系统提示里的命名空间
    version="1.0.0",
    tools=[get_weather],         # 传入 @tool 函数
)

options = Options(
    model=Options.model_from_env(),
    extra_tools=[weather],       # 挂进配置（可给多个单元）
)
```

> **对照 Rust**：`create_sdk_mcp_server()` 对应 Rust 的 `FunctionTools`（命名能力单元）——同一概念，Python 侧用函数式命名，Rust 侧沿用 builder。

### 相关类型：SdkMcpTool / CapabilityUnit {#tool-types}

两个函数各产出一种句柄类型，你不直接构造它们，只在类型标注里遇到：

```python
# @tool(...) 的产物：单个可挂载的工具单元（不透明句柄）
class SdkMcpTool: ...

# create_sdk_mcp_server(...) 的产物：一个命名能力单元 = namespace + 一组工具
# 挂进 Options.extra_tools；对应 Rust 的 FunctionTools
class CapabilityUnit: ...
```

| 类型 | 谁产出 | 用途 |
| --- | --- | --- |
| `SdkMcpTool` | `@tool` 装饰后的函数 | 传给 `create_sdk_mcp_server(tools=[...])` |
| `CapabilityUnit` | `create_sdk_mcp_server()` | 传给 `Options(extra_tools=[...])` |

## 命名空间进入构建期校验 {#build-checks}

命名能力单元作为薄 primitive，和内置 primitive 一样进入装配 agent 时的**构建期**校验：

- 工具重名 → `DuplicateTool`
- 命名空间撞名 → `DuplicateVariableName`

也就是说撞名会在装配 agent 时**立即报错**，而不是运行到一半才炸。错误体系见 [错误处理](/sdk-py/errors#build-checks)。

## MCP：另一类工具来源

一个 MCP server 暴露的工具会作为一类 primitive 挂进 agent。传输配置面（`McpServerConfig` 家族）：

| 能力 | v1 | 状态 |
| --- | --- | --- |
| 挂载一个 MCP server | `Options(mcp_servers=[url, ...])`（糖） | 🟢 |
| 富配置（Stdio/SSE/Http、鉴权头等） | 目前糖只收 URL | 🟡 待扩 |
| 运行时控制（`get_mcp_status` / `reconnect` / `toggle`） | — | 🟠 未实现 |

MCP 服务端契约见 MCP 接入（Rust/core 侧，契约跨语言一致）。

## ToolAnnotations：工具行为提示（架构占位）

::: warning 架构已规划、尚未实现（🟠）
`ToolAnnotations` 给工具附带行为提示（`readOnlyHint` / `destructiveHint` / `idempotentHint` / `openWorldHint`），供权限层与 UI 判断危险性。v1 **未实现**。
:::

规划形态（草案）：在 `@tool(...)` 里以 `annotations=` 传入，形如 `@tool("search", "...", {"query": str}, annotations=ToolAnnotations(read_only_hint=True))`。它落地前，v1 对工具危险性没有结构化标注——控制手段只有装配期的「装/不装」，见 [权限模型](/sdk-py/permissions)。

## 相关

- [Options 配置](/sdk-py/options) · [错误处理](/sdk-py/errors) · [权限模型](/sdk-py/permissions) 🟠
- 对照 Rust：[自定义工具](/sdk/tools)
