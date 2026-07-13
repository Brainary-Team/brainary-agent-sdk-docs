---
outline: 2
---

# 权限模型（Python）

> **读完本页你能**：分清「装了哪些工具（可用性）」与「这次准不准调（授权）」是两回事；掌握 agent 授权控制面的 6 个真实权限模式、`allowed_tools` / `disallowed_tools` 声明式规则、`can_use_tool` 逐次回调与 `ToolPermissionContext`、`PermissionResult` 裁决、以及 `PermissionUpdate` 运行期改规则机制的 Python 规划形态。

::: warning 规划：Python 接口面（镜像 Rust）
下方签名为设计形态、尚未实现。Rust 侧见 [Rust：权限模型](/sdk/permissions)。
:::

**状态图例（全站统一 4 态）**：🟢 已实现 · 🟡 类型/旋钮就位待上游 · 🟠 架构已规划未实现 · ⚪ 暂缓/仅登记

本页整面是 **🟠 架构已规划未实现**：授权控制面尚未落地，但下面的类型、字段、参数都是**已承诺的形态**，供上游对齐，不是占位草案。

## 为什么需要权限面

权限是 agent 的**控制面（control plane），不是一个布尔开关**。当模型请求调用一个有副作用的工具（写文件、发网络请求、跑 shell 命令），总得有人回答「**这一次**准不准调？」。这套「谁来答、按什么答、答完能不能改」的机制就是权限面。

关键是把两件常被混为一谈的事分开——Brainary 是**刻意**分开的：

- **可用性（availability）＝ 装了哪些工具**：agent 只能看到你在装配期挂进 `Options` 的工具。没装的能力，模型感知不到。这是**静态**的粗粒度边界。
- **授权（authorization）＝ 这次准不准调**：即便工具装上了、对模型可见，具体某次调用仍要过授权判定——自动放行 / 拒绝 / 弹回你的回调裁决。这是**动态、逐次**的细粒度控制。

工具「可用」不等于「每次调用都被批准」。本页讲的模式、规则、回调、裁决全属于授权。装配期约束见末尾 [与装配期手段的关系](#与装配期手段的关系)。

## PermissionMode —— 6 个真实模式

权限模式是授权面的**全局档位**。它不是三选一的玩具，而是 6 个各自承载不同自主度的真实模式，用字符串字面量表达（与 Rust 枚举一一对应）。

```python
# 🟠 架构已规划未实现。承诺形态。
from typing import Literal

PermissionMode = Literal[
    "default",            # 标准权限行为：未预批的有副作用调用走 can_use_tool 裁决
    "acceptEdits",        # 自动接受文件编辑，其余照常。快速迭代常用默认
    "plan",              # 规划模式：只探索不改动，改动前须 exit_plan_mode
    "dontAsk",           # 未预批一律直接拒绝，而非询问。适合无人值守白名单
    "bypassPermissions", # 跳过权限检查（显式 ask 规则仍拦）。危险，仅可信环境
    "auto",              # 由模型分类器逐次判定放行/拒绝
]
```

| 模式 | 语义 | 映射的 Brainary 自主度档 |
| --- | --- | --- |
| `"default"` | 有副作用调用走回调裁决 | 有人值守 · 逐次把关 |
| `"acceptEdits"` | 自动接受文件编辑，其余照常 | 半自主 · 编辑放手（迭代默认） |
| `"plan"` | 只探索不改动，改动前须 `exit_plan_mode` | 只读侦察 · 计划先行 |
| `"dontAsk"` | 未预批一律拒绝，不询问 | 无人值守 · 白名单封闭 |
| `"bypassPermissions"` | 跳过检查（ask 规则仍拦） | 全放手 · 仅可信环境 |
| `"auto"` | 模型分类器逐次判定 | 模型自裁 · 委托判断 |

其中 `"plan"` 与 `"acceptEdits"` 是一等公民：

- **`"plan"`（规划模式）**：让 agent「只看不动」——读代码、跑分析、列方案，但**不落地任何改动**。要真正动手，模型须调用 `exit_plan_mode` 显式退出并拿到批准。原生支持「先给我看计划再执行」的工作流。
- **`"acceptEdits"`（自动接受编辑）**：文件编辑不再逐次弹窗，直接放行——**快速迭代场景的推荐默认**。其它有副作用调用（shell、网络）仍照常裁决，兼顾速度与安全。

## allowed_tools / disallowed_tools —— 声明式规则

除了逐次回调，还有一层**声明式**静态规则，直接挂在 `Options` 上，无需写代码即可表达「这些自动批、这些一律拒」。

```python
# 🟠 架构已规划未实现。承诺形态。
Options(
    model="...",
    allowed_tools=["Read", "Grep", "Bash(git status)"],   # 自动批准，不弹回调
    disallowed_tools=["WebFetch", "Bash(rm *)"],          # 拒绝
    permission_mode="default",
)
```

规则语义要点：

- **`disallowed_tools` 里的裸工具名**（如 `"WebFetch"`）：把该工具**从模型上下文里彻底移除**——模型看不到、也调不了。
- **作用域规则**（如 `"Bash(rm *)"`）：工具仍可用，但**任何模式下**（包括 `"bypassPermissions"`）匹配到的调用都被拒绝。命令级黑名单靠它。
- **`allowed_tools` 是自动批准，不是限定集**：列进去的免过回调直接放行；但它**不会**把 agent 限制成「只能用这些」——没列到的工具照样可用，只是要落到 `permission_mode` 与 `can_use_tool` 裁决。要真正禁用，用 `disallowed_tools`。

裁决优先级：先看声明式规则（allow/deny），命中即定；未命中再看 `permission_mode`；仍需询问才落到 `can_use_tool`。

## can_use_tool 逐次回调 + ToolPermissionContext

当声明式规则和模式都没拍板、流程解析为「需要问一次」时，才调用 `can_use_tool`。它是**异步**的，拿到工具名、入参，以及一个 `ToolPermissionContext`——上下文是**回调自己的入参**，是一等核心类型，不是内部管线。

```python
# 🟠 架构已规划未实现。承诺形态。
from typing import Any, Awaitable, Callable
from dataclasses import dataclass, field

# 逐次工具授权回调：仅在权限流解析为「需询问」时被调用。
# 已被 allowed_tools / 规则 / acceptEdits|bypassPermissions 放行的调用不会触发它。
CanUseTool = Callable[
    [str, dict[str, Any], "ToolPermissionContext"], Awaitable["PermissionResult"]
]

@dataclass
class ToolPermissionContext:
    suggestions: list["PermissionUpdate"] = field(default_factory=list)  # 可持久化的规则建议
    blocked_path: str | None = None       # 触发本次请求的被拦路径（越界访问等）
    decision_reason: str | None = None    # 本次询问被触发的原因（PreToolUse hook 返回 "ask" 时转发）
    prompt: str | None = None             # 完整询问提示句，如「agent 想读取 foo.txt」
    signal: Any | None = None             # 预留：中断信号支持
```

挂进配置：`Options(model=..., can_use_tool=my_callback)`。

**`can_use_tool` 回调参数**（`async (tool_name, input_data, context) -> PermissionResult`）：

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `tool_name` | `str` | 本次被请求调用的工具名 |
| `input_data` | `dict[str, Any]` | 模型给该工具的入参；可在 `Allow` 里改写后放行 |
| `context` | `ToolPermissionContext` | 本次调用的上下文（一等核心类型，见上） |

`ToolPermissionContext` 让回调**基于上下文**决策，而非只看工具名：`suggestions` 给可持久化的规则建议、`blocked_path` 指出踩到的沙箱边界、`decision_reason` 说明为什么走到询问、`prompt` 提供现成的人类可读提示文案。

> 要**无条件拦截每一次**工具调用（含被规则/模式放行的），用 [PreToolUse hook](/sdk-py/hooks) 而非 `can_use_tool`——后者只在流程解析为「需询问」时触发。

## PermissionResult —— 裁决

回调返回 `PermissionResultAllow` 或 `PermissionResultDeny`。

```python
# 🟠 架构已规划未实现。承诺形态。
from typing import Literal

@dataclass
class PermissionResultAllow:
    behavior: Literal["allow"] = "allow"
    updated_input: dict[str, Any] | None = None            # 改写后的入参；None = 原样放行
    updated_permissions: list["PermissionUpdate"] | None = None  # 顺带持久化的规则

@dataclass
class PermissionResultDeny:
    behavior: Literal["deny"] = "deny"
    message: str = ""       # 拒绝理由，回灌给模型让它换招
    interrupt: bool = False # 是否顺带中断本次运行，而非仅拒这一次调用

PermissionResult = PermissionResultAllow | PermissionResultDeny
```

- **`updated_input`**：放行时**改写入参**——批准的同时纠正/脱敏模型给的参数，模型拿到改写后的版本执行。`None` 表示原样放行。
- **`updated_permissions`**：放行时**落一条规则**——把本次决定沉淀成持久规则（常见做法：把 `context.suggestions` 原样塞回），下次同类调用免问。
- **`message`**：拒绝理由回灌给模型，引导换招。
- **`interrupt`**：为 `True` 时不只拒这一次，而是**中断整个运行**——踩到硬红线要立即刹车时用。

## PermissionUpdate / PermissionRuleValue —— 运行期改规则

`updated_permissions` 里塞的、以及运行期 `set_permission_mode` 背后动的，是同一套**规则变更机制**。它是**公开机制**，不是内部实现细节——凡是想在运行中动态改授权（切模式、加规则、放开目录）都走它。

```python
# 🟠 架构已规划未实现。承诺形态。
from typing import Literal

@dataclass
class PermissionUpdate:
    type: Literal[
        "addRules", "replaceRules", "removeRules",
        "setMode",
        "addDirectories", "removeDirectories",
    ]
    rules: list["PermissionRuleValue"] | None = None            # add/replace/remove 的规则集
    behavior: Literal["allow", "deny", "ask"] | None = None     # 规则操作的行为
    mode: PermissionMode | None = None                          # setMode 要切到的模式
    directories: list[str] | None = None                       # add/remove 目录操作的目录集
    destination: (
        Literal["userSettings", "projectSettings", "localSettings", "session"] | None
    ) = None   # 更新落到哪里（决定作用域与是否跨会话持久）

@dataclass
class PermissionRuleValue:
    tool_name: str                        # 目标工具名，如 "Bash"
    rule_content: str | None = None       # 作用域内容，如 "git status"、"rm *"；None = 整工具粒度
```

**`destination` 取值**：`"userSettings"`（用户级）· `"projectSettings"`（项目级）· `"localSettings"`（项目本地 `.local`，跨会话持久）· `"session"`（仅本会话）。

一句话：`set_permission_mode` 是 `PermissionUpdate(type="setMode", mode=...)` 的门面；回调里的 `updated_permissions` 是 `type="addRules"` 的门面；放开新目录是 `type="addDirectories"`。`destination` 决定这条更新「只管这次会话」还是「写进本地设置跨会话生效」。

## 权限接口一览

| Brainary 类型 | 规划形态 | 状态 |
| --- | --- | --- |
| `PermissionMode`（6 态字面量） | 6 态 `Literal` | 🟠 |
| `allowed_tools` / `disallowed_tools`（Options 字段） | `Options(allowed_tools=[..], disallowed_tools=[..])` | 🟠 |
| `CanUseTool`（async 回调） | 回调类型 + `Options(can_use_tool=..)` | 🟠 |
| `ToolPermissionContext` | 一等核心 dataclass | 🟠 |
| `PermissionResultAllow` / `PermissionResultDeny` | dataclass | 🟠 |
| `PermissionUpdate` / `PermissionRuleValue` | dataclass | 🟠 |

## 与装配期手段的关系 {#v1-means}

授权面（本页）是**动态、逐次**控制；它之上还有一层**静态、装配期**的粗粒度边界，二者互补：

- **装/不装即可用性边界**：agent 只能调用你显式挂载的工具/primitive——不装的能力模型碰不到。最粗最硬的一道墙（见 [Options](/sdk-py/options)）。
- **文件夹沙箱**：把文件读写钉在给定目录内，越界访问触发 `blocked_path`。
- **构建期校验**：工具重名、命名空间冲突在装配时当场报错。

装配期决定「装了什么、能碰哪个目录」（可用性）；本页的模式/规则/回调/裁决决定「装上的东西这一次准不准用、用之前改不改」（授权）。

## 桥接

授权治理不止本页一条路，它和这些面协同：

- **[Hooks](/sdk-py/hooks)**：`PreToolUse` gate 能无条件拦下**每一次**工具调用（`can_use_tool` 只在「需询问」时触发）；`PermissionRequest` hook 也参与授权流。
- **[会话/客户端方法](/sdk-py/sessions)**：运行期用 `set_permission_mode` 动态切档，背后就是 `PermissionUpdate(type="setMode")`。
- **[内置工具目录](/sdk-py/builtin-tools)**：命令级沙箱与 bash 工具配套——`"Bash(rm *)"` 这类作用域拒绝规则针对的正是它。

## 相关

- [Hooks 子系统](/sdk-py/hooks) —— PreToolUse gate 与 PermissionRequest hook
- [内置工具目录](/sdk-py/builtin-tools) —— bash 工具与命令沙箱
- [自定义工具](/sdk-py/tools) —— 工具怎么装进 agent（可用性）
- [Options 统一配置](/sdk-py/options) —— 装配期能力约束与沙箱
- [会话管理](/sdk-py/sessions) —— 运行期 `set_permission_mode` 切档
- [边界与路线图](/sdk-py/limits) —— 覆盖矩阵与里程碑
- 对照 Rust：[权限模型](/sdk/permissions)
