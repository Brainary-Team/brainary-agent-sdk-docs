---
outline: 2
---

# Options 统一配置（Python）

> **读完本页你能**：用 `Options(...)` dataclass 配好模型、系统提示、内置能力糖与逃生口，分清「糖」与「逃生口」，并知道 `model` 未设时会报错。

::: warning 规划：Python 接口面（镜像 Rust）
下方签名为设计形态、尚未实现，见 [总览](/sdk-py/overview) 的规划横幅。Rust 侧的等价物见 [Rust：Options](/sdk/options)。
:::

`Options` 是 SDK 唯一的配置对象，由 `query()` 与 `BrainaryClient` 共用。它是一个 **dataclass**——用关键字参数直接构造，**只有 `model` 必填**。

> **先认两个词**：
> - **糖**：便捷开关，SDK 替你把常用能力一行装好（如 `enable_memory=True`），覆盖绝大多数场景。
> - **逃生口（escape hatch）**：当糖不覆盖你的需求时的兜底通道——塞进任意自定义能力（`extra_primitive` / `extra_tools`）。

## 一眼看全

```python
from brainary_agent_sdk import Options

options = Options(
    model=Options.model_from_env(),      # 必填
    system_prompt="你是一个……",          # 系统提示（三选一，见下）
    enable_memory=True,                  # 糖 → 工作记忆
    project_dir="/path/to/workspace",    # 糖 → 文件夹沙箱
    mcp_servers=["https://host/mcp"],    # 糖 → MCP（可给多个）
    extra_tools=[weather],               # 逃生口：一组轻量自定义工具
    extra_primitives=[my_prim],          # 逃生口：任意 primitive
    max_turns=12,                        # 循环护栏
    billing_cap=10,                      # 预算上限（缺省 10.0）
)
```

## 字段逐项

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `model` | **必填** | 用哪个模型、怎么连（`ModelSelection`） |
| `system_prompt` | `str \| SystemPrompt \| None` | 系统提示；给字符串即内联 Jinja2 模板（糖），见下 |
| `enable_memory` | `bool` | 糖：加工作记忆（命名空间 `working_memory`） |
| `project_dir` | `str \| None` | 糖：加文件夹沙箱（命名空间 `workspace`） |
| `mcp_servers` | `list[str]` | 糖：挂载 MCP server（目前每项收 URL） |
| `extra_tools` | `list` | 逃生口：一组命名能力单元（`create_sdk_mcp_server()` 的产物），见 [自定义工具](/sdk-py/tools) |
| `extra_primitives` | `list[Primitive]` | 逃生口：任意 primitive |
| `max_turns` | `int \| None` | 护栏：走满这么多步以 `stop_reason="max_turns"` 停 |
| `billing_cap` | `Decimal \| float \| None` | 预算上限；缺省 `10.0`。成本的**结果侧**是 `ResultMessage.total_cost_usd`，见 [消息模型](/sdk-py/messages#cost) |

> `model` 未设时，构造 `Options(...)` 或首次 `query()` / 建 client 时会抛配置异常（见下「model 未设 → 报错」）。

## 模型：ModelSelection 与 model_from_env() {#model-selection}

`model` 字段的类型是 `ModelSelection`——「用哪个模型、怎么连」。最常用的是从环境变量读取的便捷构造器 `Options.model_from_env()`：

```python
class ModelSelection:
    def __init__(
        self,
        *,
        model: str,                        # 模型名 / id
        api_key: str,                      # 接入密钥
        endpoint: str,                     # API base URL
        use_full_model_id: bool = False,   # 是否使用完整模型 id
    ) -> None: ...

class Options:
    @staticmethod
    def model_from_env() -> ModelSelection: ...
    # 从环境变量读取：OPENAI_API_KEY / OPENAI_API_MODEL / OPENAI_API_URL。
    # 三者缺一即抛配置异常（BuildError，见 /sdk-py/errors）。
```

| 构造方式 | 返回 | 说明 |
| --- | --- | --- |
| `Options.model_from_env()` | `ModelSelection` | 从 `OPENAI_API_KEY` / `OPENAI_API_MODEL` / `OPENAI_API_URL` 读取（推荐） |
| `ModelSelection(model=, api_key=, endpoint=)` | `ModelSelection` | 显式给全三项 |

> **关于 Provider**：v1 走 **OpenAI 兼容端点**——「用哪家」隐含在 `endpoint`（`OPENAI_API_URL`）里，只要对方暴露 OpenAI 兼容 API（OpenAI 官方、兼容网关、自建推理服务等）即可接入。**没有独立的多-provider 抽象**（如 Anthropic / Gemini 原生协议切换）；若未来要支持非兼容协议，需另加一层 provider 面。当前 `ModelSelection` 三项（model / key / endpoint）即完整接入信息。

## 系统提示：SystemPrompt

系统提示有三种来源；`system_prompt` 字段收其中常用的两种（`str` 即内联），也可给完整 `SystemPrompt`：

```python
# system_prompt: str | SystemPrompt | None
#   None   → 内置起步模板（默认）
#   str    → 内联 Jinja2 模板串（= SystemPrompt.inline(...)）
#   SystemPrompt.template_file(path) → 从文件读取
class SystemPrompt:
    @staticmethod
    def default() -> "SystemPrompt": ...            # 内置起步模板（等价于不设 system_prompt）
    @staticmethod
    def inline(template: str) -> "SystemPrompt": ... # 内联 Jinja2 模板串（= 直接传 str）
    @staticmethod
    def template_file(path: str) -> "SystemPrompt": ... # 从文件读取；装配 agent 时才读盘
```

| 来源 | 怎么设 | 含义 |
| --- | --- | --- |
| `Default`（默认） | 不设 `system_prompt` | 用内置起步模板 |
| `Inline` | `system_prompt="……"` | 直接内联 Jinja2 模板字符串 |
| `TemplateFile` | `system_prompt=SystemPrompt.template_file(path)` | 从文件读取；装配 agent 时才读盘 |

- **不设时**默认走内置模板，无需写任何提示。
- 模板是 **Jinja2**：能力糖与自定义工具注入的变量都能在模板里 `{% if … %}` 门控。

## 糖 vs 逃生口

- **糖**（`enable_memory` / `project_dir` / `mcp_servers`）：SDK 替你把常用能力装配成 primitive，你不必知道 primitive 的类型名。
- **逃生口**（`extra_primitives` / `extra_tools`）：糖不够用时，`extra_primitives` 收任意 primitive，`extra_tools` 收一组 `@tool` 打包的轻量工具。两者一起进入构建期的工具去重与命名空间校验——撞名在装配 agent 时报错（见 [错误处理](/sdk-py/errors)）。

## model 未设 → 报错

`model` 是唯一必填项。忘了设，装配 agent 时抛配置异常（异常体系见 [错误处理](/sdk-py/errors)）：

```python
import pytest
from brainary_agent_sdk import query, Options

with pytest.raises(Exception):
    # 缺 model：构造/装配阶段抛配置异常
    async for _ in query(prompt="hi", options=Options(enable_memory=True)):
        pass
```

## 目标配置面（规划中，🟠）

> 图例：🟠 已落地（上表）· 🟠 已规划、字段名已定、尚未实现。
>
> 上面的字段逐项表覆盖当前 🟠 面；但要成为一只完整的编码 agent SDK，`Options` 还欠一整块**表面积**——权限、hooks、子 agent、设置来源、沙箱、插件、推理控制等。这块是**规划形态**，字段名（snake_case）如下已定，随底层架构推进逐项落地。Rust 侧等价物见 [Rust：Options](/sdk/options)。

以下都是 `Options(...)` 的 🟠 dataclass 字段，与 🟠 字段自由混用；必填项仍只有 `model`。

| 字段（🟠 规划） | 类型 | 说明 |
| --- | --- | --- |
| `permission_mode` | `PermissionMode \| None` | 权限模式：`"default"` / `"acceptEdits"` / `"plan"` / `"dontAsk"` / `"bypassPermissions"` / `"auto"`。见 [权限](/sdk-py/permissions) |
| `allowed_tools` | `list[str]` | 免确认自动放行的工具名/规则；**不**限制成只用这些，未列中的落到 `permission_mode` / `can_use_tool`。见 [权限](/sdk-py/permissions) |
| `disallowed_tools` | `list[str]` | 拒绝的工具；裸名 `"Bash"` 从上下文移除，作用域规则 `"Bash(rm *)"` 在任何模式（含 bypass）拒绝匹配调用。见 [权限](/sdk-py/permissions) |
| `can_use_tool` | `CanUseTool \| None` | 权限回调 `async (tool_name, input, ctx) -> PermissionResult`；仅当权限流「落到 prompt」时才触发。见 [权限](/sdk-py/permissions) |
| `hooks` | `dict[HookEvent, list[HookMatcher]] \| None` | 按 `HookEvent` 键挂拦截回调；生命周期事件切面。见 [Hooks](/sdk-py/hooks) |
| `agents` | `list[AgentDefinition] \| None` | 程序化子 agent：每个带 `prompt` / `tools` / `model` / `permission_mode` / `max_turns` / `background`。SDK **一等配置面**（非 core-only）；深度装配见 core agent |
| `setting_sources` | `list[SettingSource] \| None` | 加载哪些磁盘设置：`"user"` / `"project"` / `"local"`（含项目内存文件）。**传 `[]` = 完全 hermetic**，一切来自程序化配置，利于 CI 复现 |
| `add_dirs` | `list[str \| Path]` | 追加根目录外的额外可访问目录（多仓工作） |
| `sandbox` | `SandboxSettings \| None` | 约束工具（尤其内置 bash）的文件/命令/网络作用域；随内置 bash 工具落地。见 [内置工具](/sdk-py/builtin-tools) 与 [权限](/sdk-py/permissions) |
| `plugins` | `list[PluginConfig]` | 程序化加载本地插件包（打包的 commands/agents/mcp）；每项 `{"type": "local", "path": ...}` |
| `thinking` | `ThinkingConfig \| None` | 扩展思考：`{"type": "adaptive"}` / `{"type": "enabled", "budget_tokens": N}` / `{"type": "disabled"}`（+ 可选 `display`）。多半归拢到底层 `llm_settings` |
| `effort` | `EffortLevel \| None` | 思考深度档：`"low"` / `"medium"` / `"high"` / `"xhigh"` / `"max"`。多半归拢到底层 `llm_settings` |
| `output_format` | `OutputFormat \| None` | 令响应符合 JSON schema：`{"type": "json_schema", "schema": {...}}`；对库调用尤其有用 |
| `fallback_model` | `ModelSelection \| None` | 主模型失败时的次选模型 |
| `enable_default_tools` | `bool` | 一键装上标准内置工具套件（工具预设），对照现有 à-la-carte 糖（`enable_memory` 等）。见 [内置工具](/sdk-py/builtin-tools) |

### `project_dir` / `add_dirs` / cwd 的关系

- `project_dir`（🟠）：文件夹沙箱的**命名空间**（`workspace`），能力糖，把某文件夹装成可被工具操作的沙箱。
- `add_dirs`（🟠）：在此之外声明**额外可访问目录**，用于多仓/跨目录工作，不改变沙箱命名空间。
- 二者都不等同进程 **cwd**。SDK 是进程内库、不派生子进程，没有「CLI cwd」这一档；相对路径按 `project_dir`（缺省则当前进程工作目录）解析，无需也无「设 cwd」字段——这是与 CLI 子进程模型的关键差异。

### 命令沙箱 vs PoA/wasm 边界（勿混）

`sandbox` 与 PoA 宿主 的隔离是**两个不同层级**：

- **PoA / wasm 边界**：隔离**整只 `.poa` 客户程序**——一个 agent 程序作为不可信客体在 wasm 沙箱里运行，宿主控制其系统调用面。
- **命令沙箱（`sandbox`）**：在**宿主内部**约束单个内置工具（尤其 bash）能碰的文件/命令/网络，是工具级作用域，不是程序级隔离。

即：PoA 管「谁在运行」，命令沙箱管「宿主里的 bash 能干什么」。命令沙箱随内置 bash 工具落地，见 [内置工具](/sdk-py/builtin-tools) 与 [权限](/sdk-py/permissions)。

### 确认不纳入（逃生口 / OUT）

以下字段**不进** `Options`，或已由现有面吸收：

| 字段 | 处置 |
| --- | --- |
| `extra_args` | 由现有逃生口 `agent_config` / `llm_settings` 吸收——进程内库无「透传 CLI flag」一说 |
| `stderr` / `debug_stderr` | 对应现有 `debug_dump`（显式落盘），不复制 stderr 回调 |
| `max_buffer_size` / `cli_path` / `settings` / `user` / `env` | 皆属 **CLI 子进程管线**（stdout 缓冲、CLI 路径、设置文件路径、用户标识、子进程环境变量），进程内库无对应，**OUT** |

> `thinking` / `effort` 虽列为独立字段便于发现，落地时多半归拢进底层 `llm_settings`；`setting_sources=[]` 即 hermetic，是 SDK-only / CI 场景的推荐姿势。

## 相关

- [两个入口](/sdk-py/query-and-client) · [自定义工具](/sdk-py/tools) · [错误处理](/sdk-py/errors)
- 对照 Rust：[Options](/sdk/options)
