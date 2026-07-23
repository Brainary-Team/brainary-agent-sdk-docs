# 官网首页性能优化设计

日期：2026-07-15
分支：`dev/homepage-perf`

> ⚠️ **本文为实施前的设计快照，其元凶排序已被实测推翻，第二／三档方案均未进入最终方案。**
> **最终结论与完整实测数据见同目录 `2026-07-15-homepage-perf-final.md`。** 本文仅存档设计过程。
>
> 简述：第二档（shadowBlur → 预渲染精灵）实测为负优化，废弃；
> 第三档（background-size → transform）在 Apple M4 上零可测收益、
> 且是唯一有视觉差异的项，违反「保证当前效果」硬约束，撤销。
> **最终落地的只有第一档（B / E）+ favicon。**

## 背景

用户在 MacBook Air（无风扇、被动散热）上打开官网，设备发烫严重。

这不是加载性能问题。首页产物已经很轻：HTML 7 kB (gzip) + CSS 7 kB + JS 10.6 kB ≈ 25 kB，
加字体约 175 kB，无图片、无 CDN 外链、无框架运行时。压缩／分包／tree-shaking 没有空间。

真正的问题是**持续渲染功耗**：页面在静止状态下仍在满帧烧 CPU/GPU。

## 诊断

按功耗排序（读代码得出，非 profile 实测；改造后用 Playwright 量帧耗时验证）：

1. **`ctx.shadowBlur`（`src/neural.js:137`、`:164`）—— 首要元凶。**
   canvas 2D 的 shadowBlur 是逐次绘制的高斯模糊，基本吃不到 GPU 加速。
   每帧约 100 次带模糊绘制（70 节点 + 6 信号 × 5 拖尾点），60fps ≈ **每秒 6000 次全模糊填充**，
   且在 Retina dpr=2 的全屏画布上。

2. **canvas 滚出视口不停渲染。** 无 IntersectionObserver，滚到 footer 时 Hero 神经场仍满帧跑。
   仅切标签页才暂停（`src/neural.js:256`）。

3. **`field-breathe` 动画动 `background-size`（`src/style.css:85-92`）。**
   background-size 非可合成属性，动它 = 每帧重新栅格化整个视口的固定背景层，
   且带 `mask-image`，14s 一轮无限循环、永不停止。鼠标不动也在烧。

4. **`noise-field` 的 `mix-blend-mode: overlay`（`src/style.css:101`）** 铺满全屏，
   强制整个背景栈反复混合，放大第 3 条的代价。

5. **每帧 `getBoundingClientRect()`（`src/neural.js:73`）** —— 每帧强制同步布局。
   原注释称"避免在事件回调里强制重排"，但挪进 rAF 同样是每帧一次强制布局。

6. **连线 O(n²)**（70 节点 = 2415 对 × `Math.hypot`/帧）。相对小头。

7. **`visibilitychange` 双循环隐患（`src/neural.js:256-259`）。**
   快速切换标签页可能叠出两条 rAF 链 = 双倍功耗。

## 约束

**硬约束：保证当前视觉效果不变。** 降功耗不得以牺牲观感为代价。

明确不做：
- **不降 dpr**（保持封顶 2）—— 线条会变软，看得见。
- **不砍 `noise-field` 的 `mix-blend-mode`** —— 它是静态的，代价来自下方 C 层重绘逼它反复混合；
  修好 C 后大概率自动变便宜。先量再说，便宜就留着（它对压住渐变塑料感有用）。
- **不动**节点密度、帧率、光晕强度、颜色。

## 方案

按"是否真的零视觉变化"分三档执行。

### 第一档：数学上等价，零风险

| 项 | 改动 | 为何零视觉变化 |
|---|---|---|
| B | canvas 挂 `IntersectionObserver`，离开视口 `cancelAnimationFrame` | 看不见时不画，定义上无法影响观感 |
| E | 缓存 rect，改在 `ResizeObserver` + `scroll`(passive) 更新 | 计算结果完全相同，仅消除每帧强制布局 |
| F | 连线先比较距离平方，仅命中时开方 | 同样的数学、同样的结果（`d` 后续算弧度/透明度仍需要） |
| — | rAF 收敛为带 `running` 标志的 `start()`/`stop()` | 修双循环隐患；正常路径行为不变 |

### 第二档：`shadowBlur` 缓存（最大头，需截图验收）

**不换算法** —— 高斯模糊与径向渐变衰减曲线不同，换了就是效果变了。

**用 `ctx.shadowBlur` 本身把光晕预渲染进离屏 canvas，之后每帧 `drawImage` 贴缓存。**
同一个光栅化器 → 同样的像素，只是从每秒 6000 次降到启动时算几百次。

缓存键：`(颜色, 半径, 模糊值)`。半径随呼吸连续变化，量化到 **0.1px**
（dpr=2 下 = 0.2 物理像素差异）。模糊值仅在指针邻域节点（`e > 0`）变化，量化到 1px。

风险：量化差异属于"判断不可见"，非"保证不可见"。
**验收：同帧 A/B 截图逐像素比对，用户眼睛过了才算数；不过关退回第一档。**

### 第三档：`field-breathe`（需截图验收）

`background-size` 动画 → `transform: scale` + `opacity`（均可合成，走 GPU，零重绘）。

差异：`background-size` 从左上角重新平铺，`transform` 从中心缩放。
缓解：`transform-origin: 50% 26%` 对齐 mask 中心。
幅度仅 5%、opacity 0.35、上压噪点层 —— 判断不可见，同样交给截图验收。

### 附带：favicon

现状：透明底 + 青绿节点（`#2ff0cf` / `#7dffe4`），浏览器白底标签页上对比度过低。

改法：垫一层 `--color-void`（`#04050a`）深色圆底，青绿神经网络落在上面。
与官网深色调一致，白底黑底标签页都看得清。位置：`website/index.html` 内联 SVG favicon。

## 验收

1. 每一档改完用 Playwright 量实际帧耗时，让用户看到每项换来多少。
2. 第二、三档提供同帧 A/B 截图供用户逐像素比对。
3. 构建通过、无 CDN 外链自检通过（`./build.sh`）。
