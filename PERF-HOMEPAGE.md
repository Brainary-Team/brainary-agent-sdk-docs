# 官网首页性能优化 · 分析与交接

- 日期：2026-07-15
- 分支：`dev/homepage-perf`
- 状态：**三项确定性优化已落地；已在 Apple M4 上多方法实测验证（见 §9）**

---

## 1. 需求

用户在 **MacBook Air**（无风扇、被动散热）上打开官网，**设备发烫严重**。
附带需求：favicon 颜色偏浅，在浏览器白底标签页上不好看。

**硬约束：保证当前视觉效果不变。** 降功耗不得以牺牲观感为代价。

## 2. 第一个判断：方向错了

初查产物体积：

| 项 | 大小 (gzip) |
|---|---|
| HTML | 7 kB |
| CSS | 7 kB |
| JS | 10.6 kB |
| 字体 (8× woff2) | ~175 kB |
| **合计** | **~200 kB** |

无图片、无 CDN 外链、无框架运行时。**压缩／分包／tree-shaking 没有任何空间。**

发烫**不是加载性能问题，是持续渲染功耗问题** —— 页面在静止状态下仍在满帧烧 CPU/GPU。
后续分析全部围绕"每帧干多少活"展开，不再看体积。

## 3. 分析过程（含被推翻的假设）

> ⚠️ **这一节记录了推理如何出错，请连同结论一起读。**
> 最初的元凶排序是**错的**，且排序被实测**倒过来了**。

### 3.1 初始假设（读代码得出）

按"猜测的功耗"排序：

1. `ctx.shadowBlur`（`website/src/neural.js:137`、`:164`）—— 每帧约 100 次带模糊绘制，
   60fps ≈ 每秒 6000 次全模糊填充。**判定为首要元凶。**
2. canvas 滚出视口不停渲染（无 IntersectionObserver）。
3. `field-breathe` 动 `background-size`（`website/src/style.css:85-92`）→ 全屏重栅格化。
4. `noise-field` 的 `mix-blend-mode: overlay`（`website/src/style.css:101`）→ 强制全栈混合。
5. 每帧 `getBoundingClientRect()`（`website/src/neural.js:73`）→ 每帧强制同步布局。
6. 连线 O(n²) + `Math.hypot`（62 节点 = 1891 对/帧）。

### 3.2 测量方法的两次修正

**第一次测量（错的）**：测 rAF 帧间隔 → 稳定 60.2fps、无掉帧。
**为何无效**：rAF 被 vsync 锁死，只要不掉帧就看不出开销。发烫是"每帧干多少活"，不是"掉不掉帧"。

**第二次测量（仍不完整）**：劫持 `requestAnimationFrame` 抓到 `step()` 本体计时 → **0.3 ms/帧**。
**为何不完整**：canvas 2D 的绘制指令先记录进 display list，之后才光栅化。
shadowBlur 的高斯模糊**根本不在 rAF 回调里发生**，这个数把真正的大头漏掉了。

**第三次测量（有效）**：用 `ctx.getImageData(0,0,1,1)` **强制结算**排队的绘制指令，
并按 MacBook Air 真实条件复刻负载（1440×900 @ dpr 2 → 画布 2880×1800）。

### 3.3 实测结果

每帧毫秒，已扣除 `clearRect + flush` 底噪（0.747ms）：

| 负载 | 净耗时/帧 | 结论 |
|---|---|---|
| 62 节点 + 实时 `shadowBlur` | **0.49 ms** | 便宜，不是元凶 |
| 62 节点 + 预渲染精灵（拟议的"优化"） | **0.80 ms** | **负优化，慢 1.7×** |
| 连线（O(n²) + `quadraticCurveTo`） | **1.73 ms** | canvas 内最大头 |

纯 JS（完全不碰 canvas）：

| 负载 | 耗时/帧 |
|---|---|
| 连线循环（`Math.hypot`，1891 对） | **0.0353 ms** |
| 连线循环（先比距离平方，命中才开方） | **0.0047 ms** |

### 3.4 被推翻的三条结论

| 原结论 | 实测 | 处置 |
|---|---|---|
| "`shadowBlur` 是首要元凶，每秒 6000 次全模糊填充" | 仅 0.49ms/帧。节点半径才 1–3px，模糊面积极小。**把"次数多"当成了"代价大"** | ❌ 撤回 |
| "预渲染光晕精灵能省一大截" | **慢 1.7×**。81 张小 canvas 逐个 `drawImage`，调用固定开销 + 纹理切换比直接画带模糊的小圆更贵 | ❌ 废弃 |
| "连线去 sqrt 是白给的优化" | 省 **0.03 ms/帧** ≈ 零。代码改动不值得 | ❌ 废弃 |

### 3.5 关键发现

连线那 1.73ms 里**约 98% 是光栅化**（描 77 条曲线），JS 只占 0.035ms。
再对照 `step()` 全部 JS 仅 0.3ms/帧。

> **canvas 的 JS 不是问题。所有开销都在光栅化／合成层。**

### 3.6 测量环境的致命局限

```
webglRenderer: ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero)), SwiftShader driver)
```

分析在 **headless Linux + SwiftShader（纯软件光栅化，无 GPU）** 上进行。

| 数据 | 可否迁移到 MacBook |
|---|---|
| JS 计算耗时 | ✅ 两边都是 CPU，可迁移 |
| 光栅化耗时（模糊／描边／`drawImage`） | ❌ **不可迁移**。Mac 是 GPU 加速（Metal/ANGLE），模糊是 shader pass、`drawImage` 是纹理 blit，**相对代价完全可能反过来** |

**因此 3.3 的光栅化数字只能用于排除"JS 是元凶"，不能用于给 Mac 上的 GPU 负载排序。**

## 4. 当前对元凶的判断（推理，未实测）

**`grid-field` + `noise-field` 的组合，而非 canvas。**

- `grid-field` 动 `background-size` → 强制**每帧重新栅格化整个视口**（2880×1800）
- 其上压着 `noise-field` 的 `mix-blend-mode: overlay` → **逼整个背景栈每帧重新混合**
- 两者叠加，每秒 60 次，**鼠标不动也在跑，永不停止**

依据是平台无关的：**"动 `background-size` 必然触发重绘、`transform`/`opacity` 只走合成"在所有浏览器上都成立。**
相比之下 canvas 那点活（62 个小圆 + 77 条曲线）在 GPU 上大概率是毛毛雨。

**排序与 3.1 的初始假设正好倒过来。**

## 5. 已完成的优化

三项**不依赖元凶结论、无论如何都成立**的改动：

### B. 滚出视口停渲染 — `website/src/neural.js`

canvas 挂 `IntersectionObserver`，离开视口即停 rAF。
同时把 rAF 收敛为带 `running` 标志的 `start()`/`stop()`，
修掉原 `visibilitychange`（`neural.js:256-259`）**快速切标签页可能叠出两条 rAF 链 = 双倍功耗**的隐患。

渲染条件：`视口内 && 标签页可见`。

**零视觉风险** —— 看不见时不画，定义上无法影响观感。

### C. `background-size` → `transform` — `website/src/style.css`

```css
/* 前 */ @keyframes field-breathe { 0%,100% { opacity:.28; background-size:30px 30px }   50% { opacity:.4; background-size:31.5px 31.5px } }
/* 后 */ @keyframes field-breathe { 0%,100% { opacity:.28; transform:scale(1) }           50% { opacity:.4; transform:scale(1.05) } }
```

30px → 31.5px 正好是 1.05×，幅度等价。`transform` / `opacity` 均为可合成属性，走合成器，**零重绘**。
配 `transform-origin: 50% 26%` 对齐 mask 中心，让差异最小化。

**残余差异**：原方案 mask 不动、只有点阵重新平铺；新方案 mask 随元素一起缩放 5%。
幅度 5%、opacity 0.35、上压噪点层 —— **判断不可见，需你在 Mac 上肉眼验收**。

### E. 缓存 rect — `website/src/neural.js`

原代码每帧调 `getBoundingClientRect()`（原注释称"避免在事件回调里强制重排"，
但挪进 rAF 同样是**每帧一次强制同步布局**）。

改为脏标记：`scroll` / `resize` 时标脏，用到时才读。
**纯移动鼠标不再产生任何 rect 读取。** 计算结果完全相同，零视觉变化。

### 附带：favicon — `website/index.html`

垫一层 `--color-void`（`#04050a`）深色圆底，青绿神经网络落在上面。
与官网深色调一致，白底／黑底标签页都看得清。

## 5.1 落地后的实测验证

均在 headless Chromium 上对比「旧版 baseline」与「新版 optimized」两份构建产物实测。

**B — 滚出视口停渲染（生效，且能正确恢复）**

| 状态 | 旧版帧数 / 2s | 新版帧数 / 2s |
|---|---|---|
| Hero 可见 | 119 | 119 |
| 滚到页面底部（Hero 已滚出） | **120（从不停）** | **0** |
| 滚回顶部 | 120 | 120（正常恢复） |

**E — rect 缓存（生效，且滚动时正确性未丢）**

| 场景 | 旧版 `getBoundingClientRect` | 新版 |
|---|---|---|
| 指针活跃、不滚动（2s） | **120 次（每帧）** | **0 次** |
| 边滚动边动指针（1s / 63 次滚动） | ~60 次 | 19 次（标脏后才读） |

滚动时仍会重读 —— 这是必需的，否则指针坐标会算错。

**C — 视觉差异（逐像素比对）**

隔离背景层（藏掉 canvas 与全部前景），两版均冻结在 `field-breathe` 的 **7000ms 相位
（50%，scale 峰值 = 差异最大处）**，1280×800 截图逐像素比对：

| 指标 | 值 |
|---|---|
| 完全相同的像素 | **98.77%** |
| 差异 > 8/255 的像素 | **0.16%** |
| 最大单通道差异 | 23/255（9%），仅 4 个像素 |
| 有差异像素的平均差 | 3.75/255（1.5%） |

差异集中在点阵边缘的亚像素位移。0%/100% 相位两者数学上完全一致（都是 scale 1 / 30px）。
**客观上极小，但不为零 —— 仍需第 7.4 节的肉眼验收。**

> ⚠️ 以上帧数与 rect 次数可迁移（JS 层）；**但本节不含任何 GPU/光栅化耗时数据**，
> 原因见 3.6。发烫是否真的解决，只有第 7 节能回答。

## 6. 明确不做

| 项 | 原因 |
|---|---|
| 降 dpr（保持封顶 2） | 线条会变软，**看得见** |
| 砍 `noise-field` 的 `mix-blend-mode` | 它是静态的，代价来自下方 `grid-field` 重绘逼它反复混合；C 修好后**大概率自动变便宜**。先量再说 —— 它对压住渐变塑料感有用，不该白砍 |
| 预渲染光晕精灵 | 实测负优化（见 3.4） |
| 连线去 sqrt | 省 0.03ms/帧 ≈ 零（见 3.4） |
| 动节点密度／帧率／光晕强度／颜色 | 违反"保证当前效果"硬约束 |

## 7. 交接：请在 MacBook 上验证

热量在 GPU／光栅线程，**页面 JS 测不到，Linux 软件渲染也测不准 —— 只有你的设备能给出真相。**

### 7.1 验证 C 是否真的解决了发烫（最关键）

Chrome 菜单 → 更多工具 → **任务管理器**，盯住 **GPU 进程**的 CPU 占用：

1. 打开优化前的线上官网，记录 GPU 进程 CPU%
2. 打开本分支构建的版本，等 10 秒，记录同一个数字
3. 对比

### 7.2 验证第 4 节的元凶推断

在**优化前**的页面 Console 里逐条执行，每条等 10 秒看 GPU 进程 CPU% 掉多少：

```js
// 关掉点阵呼吸动画（验证 grid-field 是否元凶）
document.querySelector('.grid-field').style.animation = 'none'

// 关掉噪点混合（验证 mix-blend-mode 的代价）
document.querySelector('.noise-field').style.display = 'none'

// 关掉 canvas（验证神经场的真实代价）
document.getElementById('neural').style.display = 'none'
```

**哪条让数字掉得最多，哪条就是真元凶。** 这能一次性证实或推翻第 4 节。

### 7.3 录 profile（更细的数据）

DevTools → Performance → 录 5 秒 → 看底部 Summary 饼图的
**Rendering / Painting / GPU / Scripting** 各占多少 ms。

### 7.4 视觉验收

C 有 5% mask 缩放的残余差异（见第 5 节）。请对比优化前后的点阵呼吸效果，
**不过关就退回**：把 `field-breathe` 改回 `background-size`，只保留 B 和 E。

### 7.5 本地跑起来

```bash
git checkout dev/homepage-perf
cd website && pnpm install && pnpm run dev   # http://localhost:5174
# 或完整构建：./build.sh --serve             # http://127.0.0.1:8080
```

## 8. 待决事项

- [x] 用 7.2 证实／推翻第 4 节的元凶推断 → **见 §9，第 4 节推断被推翻**
- [ ] 7.4 视觉验收（C 的 5% mask 缩放残余差异，仍建议肉眼过一遍）

---

## 9. 验证结果（Apple M4 实测，2026-07-15）

在真机（Apple M4，macOS 26.4，真 Metal GPU）上用 **4 种方法、多轮重复**测量，
CDP 驱动系统 Chrome（1440×900 @ dpr2，画布 2770×1626），逐状态开关背景层。

### 9.1 三组测量

| 维度 | 方法 | 结果 |
|---|---|---|
| GPU 功耗 | `powermetrics gpu_power` | 整页 84mW ≈ 空白页 85mW —— **贴地板，零信号** |
| 主线程 CPU | Chrome `Performance.getMetrics`，4 轮中位数 | 全状态 ~6–7%，**各层差异在噪声内** |
| 渲染进程整体 CPU | `top` 单 PID，3 轮×5 样本 | 全状态 ~11–14%，**各层差异在噪声内，顺序甚至倒置** |

`canvas_off`／`all_off` 反而略高于「现状」，是各层信号全部低于 ±3% run-to-run 噪声的铁证。

### 9.2 被推翻 / 修正的结论

| 原结论（本文早先） | M4 实测 | 处置 |
|---|---|---|
| §4「grid-field + noise-field 是元凶」 | GPU 侧零信号；CPU 侧 background-size vs transform 差异 < 噪声 | ❌ 推翻 |
| C（background-size→transform）省下大量功耗 | 主线程与整进程 CPU **均测不出 C 的收益** | ⚠️ C 无可测收益，但作为最佳实践（transform 永不更贵）保留 |
| shadowBlur / canvas 是重负载 | canvas 开/关 CPU 差 < 噪声，GPU 零信号 | ❌ 确认非元凶（与 §3.4 一致） |

> ⚠️ 测量期间一度出现「grid_oldmode 渲染进程 162 ms/s」的强信号，经多轮干净复测确认
> **是单次 powermetrics 的瞬时噪声**，非稳态属性。单次采样不可信，此为教训。

### 9.3 真正的热源：不是「每帧多贵」，是「永不停 + 会叠加」

M4 上整页稳态仅 ~12% 单核 + 零 GPU，**单看每帧并不贵**。发烫来自两个时间维度的问题，
恰好都由 **B** 根治：

1. **滚出视口／页面不可见仍满帧渲染** —— 旧版只在切标签页才停，滚到 footer 照跑。
2. **rAF 链可叠加**（旧 `visibilitychange` 隐患）—— 快速切标签页会叠出多条 60fps 链，
   N×12% 就能把一个核心拖满、无风扇 M4 Air 逐渐焐热。

B 用 `running` 标志把 rAF 收敛为幂等的 `start()/stop()`，并挂 `IntersectionObserver`，
渲染条件收紧为「视口内 && 标签页可见」，**同时消除了「叠加」和「常驻」两个热源**。
用户确认发烫就在这台 M4 上，此为最一致的根因解释。

### 9.4 结论

- **不是 GPU 问题，也没有单一图层元凶** —— §3.1/§4 的排序在真机上不成立。
- **B 是真正解决发烫的杠杆**（停掉不可见渲染 + 堵死 rAF 叠加），零视觉风险。
- **E** 零风险保留。**C** 无可测收益但作为最佳实践保留，唯一需 §7.4 肉眼验收的项。
