---
outline: 2
---

# Options 统一配置

> **读完本页你能**：用 `Options::builder()` 逐项配好模型、系统提示、内置能力和逃生口，分清「糖」与「逃生口」，并知道 `model` 未设时 `build()` 会报错。

`Options` 是 SDK 唯一的配置对象。它由 `query()` 和 `BrainaryClient::connect()` 共用。用链式 builder 构造，**只有 `model` 必填**。

> **先认两个词**（下面的示例和表格都会反复用到）：
> - **糖**：便捷开关。SDK 替你把常用能力一行装好，你不用知道底层类型名——如 `enable_memory(true)` 就加上工作记忆。覆盖绝大多数场景。
> - **逃生口（escape hatch）**：当便捷开关不覆盖你的需求时留给你的「兜底通道」——用它塞进任意自定义能力（`extra_primitive` / `extra_tools`）。「逃生口」是通用软件术语，不是 Rust 特有；详见下文 [糖 vs 逃生口](#糖-vs-逃生口)。

## 一眼看全

```rust
use brainary_agent_sdk::{Options, ModelSelection};

// 下面是「概览」片段，示意常见字段的位置；function_tools / my_prim 需你自备。
let options = Options::builder()
    .model(ModelSelection::from_env()?)      // 必填
    .inline_prompt("你是一个……")            // 系统提示（三选一，见下）
    .enable_memory(true)                     // 糖 → 工作记忆 primitive
    .project_dir("/path/to/workspace")       // 糖 → 文件夹沙箱 primitive
    .mcp_server("https://host/mcp")          // 糖 → MCP primitive（可多次调用）
    .extra_tools(function_tools)             // 逃生口：一组轻量自定义工具（见 /sdk/tools）
    .extra_primitive(my_prim)                // 逃生口：任意 BrainaryPrimitive
    .global("tenant", serde_json::json!("acme"))   // 向保留的 global 命名空间注入模板变量
    .max_turns(12)                           // 循环护栏
    .billing_cap(brainary_agent_sdk::Decimal::from(10))  // 预算上限（缺省 10.0）
    .build()?;
```

## builder 方法逐项

| 方法 | 类型 | 说明 |
| --- | --- | --- |
| `model(ModelSelection)` | **必填** | 用哪个模型、怎么连。见下节 |
| `system_prompt(SystemPrompt)` | 系统提示 | 直接给 `SystemPrompt` 枚举值 |
| `inline_prompt(impl Into<String>)` | 系统提示 | 糖：内联 Jinja2 模板字符串 |
| `template_file(impl Into<PathBuf>)` | 系统提示 | 糖：只记下路径，模板在 `query()`/`connect()` 装配 agent 时才读盘 |
| `enable_memory(bool)` | 能力糖 | 加工作记忆 primitive（命名空间 `working_memory`） |
| `project_dir(impl Into<PathBuf>)` | 能力糖 | 加文件夹沙箱 primitive（命名空间 `workspace`） |
| `mcp_server(impl Into<String>)` | 能力糖 | 加一个 MCP primitive；可多次调用累加 |
| `extra_tools(FunctionTools)` | 逃生口 | 加一组轻量自定义工具，见 [自定义工具](/sdk/tools) |
| `extra_primitive(Box<dyn BrainaryPrimitive>)` | 逃生口 | 加任意 primitive |
| `global(key, serde_json::Value)` | 模板变量 | 向保留的 `global` 命名空间叠加一个变量 |
| `max_turns(usize)` | 护栏 | 走满这么多步后以 `StopReason::MaxTurns` 停 |
| `billing_cap(Decimal)` | 预算 | 花费上限；不设时缺省 `10.0`。成本的**结果侧**是 `ResultMessage.total_cost_usd`（见 [消息模型](/sdk/messages#cost)） |
| `llm_settings(LLMSettings)` | 底层 | 覆盖底层 LLM 参数（温度、超时、重试等） |
| `agent_config(AgentConfig)` | 底层 | 进阶 agent 配置（透传给 core） |
| `cache_key(impl Into<String>)` | 缓存 | 提示缓存键；不设时缺省 `"brainary"` |
| `debug_prefix(impl Into<String>)` | 调试 | 落盘调试文件/行的标签前缀（配合 `debug_dump`；单独设不落盘） |
| `debug_dump(DebugSink)` | 调试 | 显式开启把每次 LLM 请求/响应落盘；默认 `Off`，SDK 绝不从环境变量自动开启。见 调试与追踪 |
| `build()` | 收尾 | `-> Result<Options>`；`model` 未设则报错 |

> `Decimal`、`LLMSettings`、`AgentConfig` 都由 `brainary-agent-sdk` re-export，无需另加依赖：`brainary_agent_sdk::Decimal` / `brainary_agent_sdk::LLMSettings` / `brainary_agent_sdk::AgentConfig`。

## 系统提示：SystemPrompt

系统提示由 `SystemPrompt` 枚举（`#[non_exhaustive]`）表示，共三种来源；builder 为常用的两种提供了糖方法：

| `SystemPrompt` 变体 | 对应 builder 方法 | 含义 |
| --- | --- | --- |
| `Default`（默认值） | 不调用任何系统提示方法 | 用内置起步模板 `DEFAULT_SYSTEM_PROMPT_TEMPLATE` |
| `Inline(String)` | `inline_prompt(impl Into<String>)` | 直接内联一段 Jinja2 模板字符串 |
| `TemplateFile(PathBuf)` | `template_file(impl Into<PathBuf>)` | 从文件读取 Jinja2 模板；`Options::build()` 只存路径，真正读盘发生在 `query()`/`connect()` 装配 agent 时（文件缺失会在那时报错） |

- **不设时**默认走 `SystemPrompt::Default`——即内置模板，无需你写任何提示。
- 也可以用 `system_prompt(SystemPrompt::…)` 直接给枚举值（等价于上面两个糖方法）。
- 模板是 **Jinja2**：能力糖与自定义工具注入的变量（如 `working_memory` / `weather.enable_weather`）都能在模板里 `{% if … %}` 门控。

## 糖 vs 逃生口

- **糖**（`enable_memory` / `project_dir` / `mcp_server`）：SDK 替你把常用能力装配成 primitive，你不必知道 primitive 的类型名。它们镜像 CLI 的常用开关。
- **逃生口**（`extra_primitive` / `extra_tools`）：当糖不够用时，`extra_primitive` 收任意实现了 `BrainaryPrimitive` 的能力单元；`extra_tools` 收一组 `#[tool]` 打包的轻量工具。糖装的 primitive 与逃生口装的会一起进入构建期的工具去重（`DuplicateTool`）与命名空间校验（`DuplicateVariableName`），撞名会在 `build()`/`connect()` 阶段报错。

## 选模型：ModelSelection

`model(...)` 收一个 `ModelSelection`，两种取法：

```rust
use brainary_agent_sdk::ModelSelection;

// ① 从环境变量读（推荐；与 llmy CLI 同款变量）
let sel = ModelSelection::from_env()?;

// ② 显式构造
let sel = ModelSelection::new("gpt-4o-mini", std::env::var("OPENAI_API_KEY").unwrap())
    .endpoint("https://gateway/v1")   // 可选：第三方 / 自托管 / 网关端点
    .use_full_model_id(true);         // 可选：发规范化的 owner/name（聚合器需要）
```

- `model` 字段可以是注册表短名（`"gpt-4o-mini"`），也可以是自定义定价规格 `"name,input,output"`（每百万 token 美元）。
- `from_env()` 读取：`OPENAI_API_KEY`（必需）、`OPENAI_API_MODEL`（必需）、`OPENAI_API_URL`（可选，空=官方端点）、`LLM_FULL_MODEL_NAME`（可选，truthy → 发全 id）。
- 凭证与环境变量的完整说明见 配置——本页不重复。

> **关于 Provider**：v1 走 **OpenAI 兼容端点**——「用哪家」隐含在 `.endpoint(...)`（`OPENAI_API_URL`）里，只要对方暴露 OpenAI 兼容 API 即可接入。**没有独立的多-provider 抽象**（Anthropic / Gemini 等原生协议切换）；若未来要支持非兼容协议，需另加一层 provider 面。`ModelSelection` 三项（model / key / endpoint）即完整接入信息。

> 未在 llmy 注册表登记的模型，其上下文窗口未知（`max_input_tokens = 0`），会影响上下文溢出护栏的行为，见 [中断与护栏](/sdk/interrupt-and-guardrails)。

## model 未设 → build() 报错

`model` 是唯一的必填项。忘了设，`build()` 返回 `Err`：

```rust
let result = brainary_agent_sdk::Options::builder().enable_memory(true).build();
assert!(result.is_err());   // 报错信息含 "model"
```

## 目标配置面（规划中，🟠）

> 图例：🟠 已落地（上表）· 🟠 已规划、签名已定、尚未实现。
>
> 上面的 builder 方法逐项表覆盖了当前 🟠 面；但要成为一只完整的编码智能体 SDK，配置对象还欠一整块**表面积**——权限、hooks、子 agent、设置来源、沙箱、插件、推理控制等。这块是**规划形态**，签名如下已定，随底层架构推进逐项落地。北极星见 [SDK 总览](/sdk/overview)。

以下 builder 方法都以 🟠 加入 `Options::builder()`，与 🟠 方法可自由链式混用；`build()` 的必填项仍只有 `model`。

| 方法（🟠 规划） | 类型 | 说明 |
| --- | --- | --- |
| `permission_mode(PermissionMode)` | 权限 | 工具执行的权限模式：`Default` / `AcceptEdits` / `Plan` / `DontAsk` / `BypassPermissions` / `Auto`。见 [权限](/sdk/permissions) |
| `allowed_tools(impl IntoIterator<Item = String>)` | 权限 | 免确认自动放行的工具名/规则；**不**把模型限制成只用这些，未列中的落到 `permission_mode` / `can_use_tool`。见 [权限](/sdk/permissions) |
| `disallowed_tools(impl IntoIterator<Item = String>)` | 权限 | 拒绝的工具；裸名 `"Bash"` 从上下文移除该工具，作用域规则 `"Bash(rm *)"` 在任何模式（含 bypass）拒绝匹配调用。见 [权限](/sdk/permissions) |
| `can_use_tool(cb)` | 权限 | 权限回调 `Fn(tool_name, input, ToolPermissionContext) -> impl Future<Output = PermissionResult>`；仅当权限流「落到 prompt」时才触发。见 [权限](/sdk/permissions) |
| `hooks(HooksMap)` | Hooks | 按 `HookEvent` 键挂拦截回调（`HashMap<HookEvent, Vec<HookMatcher>>`）；生命周期事件切面。见 [Hooks](/sdk/hooks) |
| `agents(impl IntoIterator<Item = AgentDefinition>)` | 子 agent | 程序化子 agent：每个带 `prompt` / `tools` / `model` / `permission_mode` / `max_turns` / `background`。这是 SDK **一等配置面**（非 core-only）；深度装配见 core agent |
| `setting_sources(impl IntoIterator<Item = SettingSource>)` | 设置来源 | 加载哪些磁盘设置：`User` / `Project` / `Local`（含项目级记忆文件）。**传空 `[]` = 完全 hermetic**，一切来自程序化配置，利于 CI 复现 |
| `add_dir(impl Into<PathBuf>)` | 目录 | 追加一个根目录外的可访问目录（多仓工作）；可多次调用累加 |
| `add_dirs(impl IntoIterator<Item = PathBuf>)` | 目录 | 一次追加多个额外可访问目录 |
| `sandbox(SandboxSettings)` | 命令沙箱 | 约束工具（尤其内置 bash）的文件/命令/网络作用域；随内置 bash 工具落地。见 [内置工具](/sdk/builtin-tools) 与 [权限](/sdk/permissions) |
| `plugins(impl IntoIterator<Item = PluginConfig>)` | 插件 | 程序化加载本地插件包（打包的 commands/agents/mcp）；每项 `PluginConfig::local(path)` |
| `thinking(ThinkingConfig)` | 推理控制 | 扩展思考：`Adaptive` / `Enabled { budget_tokens }` / `Disabled`（+ 可选 `display`）。多半归拢到底层 `llm_settings` |
| `effort(EffortLevel)` | 推理控制 | 思考深度档：`Low` / `Medium` / `High` / `XHigh` / `Max`。多半归拢到底层 `llm_settings` |
| `output_format(OutputFormat)` | 结构化输出 | 令响应符合 JSON schema（`OutputFormat::json_schema(schema)`）；对库调用尤其有用 |
| `fallback_model(ModelSelection)` | 模型 | 主模型失败时的次选模型 |
| `enable_default_tools(bool)` | 默认工具预设 | 一键装上标准内置工具套件，对照现有 à-la-carte 糖（`enable_memory` 等）。见 [内置工具](/sdk/builtin-tools) |

### `project_dir` / `add_dir` / cwd 的关系

- `project_dir`（🟠）：文件夹沙箱 primitive 的**命名空间**（`workspace`），是能力糖，负责把某个文件夹装成一只可被工具操作的沙箱。
- `add_dir` / `add_dirs`（🟠）：在此之外声明**额外可访问目录**，用于多仓/跨目录工作，不改变沙箱命名空间。
- 二者都不等同进程 **cwd**。SDK 是进程内库、不派生子进程，因此没有「CLI cwd」这一档；相对路径按 `project_dir`（缺省则当前进程工作目录）解析，无需也无「设 cwd」开关——这是与 CLI 子进程模型的关键差异。

### 命令沙箱 vs PoA/wasm 边界（勿混）

`sandbox(...)` 与 PoA 宿主 的隔离是**两个不同层级**，务必分清：

- **PoA / wasm 边界**：隔离**整只 `.poa` 客户程序**——一个 agent 程序作为不可信客体，在 wasm 沙箱里运行，宿主控制其系统调用面。
- **命令沙箱（`sandbox`）**：在**宿主内部**约束单个内置工具（尤其 bash 工具）能碰的文件/命令/网络，是工具级作用域，不是程序级隔离。

即：PoA 管「谁在运行」，命令沙箱管「宿主里的 bash 能干什么」。命令沙箱随内置 bash 工具落地，见 [内置工具](/sdk/builtin-tools) 与 [权限](/sdk/permissions)。

### 确认不纳入（逃生口 / OUT）

以下配置字段**不进** `Options`，或已由现有面吸收：

| 字段 | 处置 |
| --- | --- |
| `extra_args` | 由现有逃生口 `agent_config(AgentConfig)` / `llm_settings(LLMSettings)` 吸收——进程内库无「透传 CLI flag」一说 |
| `stderr` / `debug_stderr` | 对应现有 `debug_dump(DebugSink)`（显式落盘），不复制 stderr 回调 |
| `max_buffer_size` / `cli_path` / `settings` / `user` / `env` | 皆属 **CLI 子进程管线**（stdout 缓冲、CLI 可执行路径、设置文件路径、用户标识、子进程环境变量），进程内库无对应，**OUT** |

> `thinking` / `effort` 虽列为独立 builder 方法便于发现，落地时多半归拢进底层 `llm_settings`；`setting_sources` 传空即 hermetic，是 SDK-only / CI 场景的推荐姿势。

## 相关

- [自定义工具：FunctionTools](/sdk/tools) · [两个入口](/sdk/query-and-client)
- [SDK 总览](/sdk/overview)
