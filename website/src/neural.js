// 会呼吸的突触场：纯 canvas，无外部库、无 CDN（方向：仿生神经 · Bionic）。
// 节点有机呼吸缩放 + 曲线突触连接 + 信号带拖尾沿突触自传导 + 轻微鼠标视差。
// 指针互动:邻域节点蓄能点亮、被轻微牵引(只偏显示坐标,离开自然回弹),
// 蓄满的节点自发放电;点击/轻点荡开一圈涟漪并激发近旁突触。
// 生物青绿为主色，紫仅偶发点缀。尊重 prefers-reduced-motion：只画一帧静态网络、不挂互动。
export function initNeural(canvas) {
  const ctx = canvas.getContext('2d', { alpha: true })
  if (!ctx) return

  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  // teal 主导（约 5/6），紫仅一点作为「异质神经元」
  const COLORS = ['#2ff0cf', '#2ff0cf', '#7dffe4', '#14b89c', '#2ff0cf', '#8f7bff']
  let w = 0, h = 0, dpr = Math.min(window.devicePixelRatio || 1, 2)
  let nodes = []
  let pulses = []
  let ripples = []
  const mouse = { x: 0.5, y: 0.5, tx: 0.5, ty: 0.5 }
  // 指针在视口中的原始坐标;active=false 时邻域效应整体衰退
  const ptr = { cx: 0, cy: 0, active: false }
  const FIELD_R = 170 // 指针影响半径
  let raf = 0
  let running = false
  // 渲染条件：视口内 && 标签页可见。任一不成立就停 rAF——看不见的帧不画。
  let inView = true
  let pageVisible = !document.hidden

  // canvas 相对视口的位置：脏标记缓存。原实现每帧取一次 rect，等于每帧强制同步布局；
  // 位置只随 scroll/resize 变，所以标脏后按需读——纯移动鼠标不再产生任何 rect 读取。
  let rectLeft = 0, rectTop = 0, rectDirty = true
  function ensureRect() {
    if (!rectDirty) return
    const r = canvas.getBoundingClientRect()
    rectLeft = r.left; rectTop = r.top
    rectDirty = false
  }

  function resize() {
    const rect = canvas.getBoundingClientRect()
    rectLeft = rect.left; rectTop = rect.top; rectDirty = false
    w = rect.width; h = rect.height
    canvas.width = w * dpr; canvas.height = h * dpr
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    const density = Math.min(70, Math.max(28, Math.round((w * h) / 21000)))
    nodes = Array.from({ length: density }, (_, i) => ({
      x: seeded(i * 1.3) * w,
      y: seeded(i * 2.7 + 5) * h,
      vx: (seeded(i * 3.1) - 0.5) * 0.2,
      vy: (seeded(i * 4.9) - 0.5) * 0.2,
      r: 0.9 + seeded(i * 6.7) * 1.8,
      // 每个节点独立的呼吸相位与速率，避免整齐划一
      phase: seeded(i * 8.3) * Math.PI * 2,
      breathe: 0.7 + seeded(i * 9.1) * 0.9,
      c: COLORS[i % COLORS.length],
      e: 0, // 指针蓄能:0~1,决定加亮/放大/自发放电
      ox: 0, oy: 0, // 指针牵引的显示偏移(不改真实位置,回弹自然)
      fired: false,
    }))
  }

  // 确定性伪随机：避免用 Math.random，布局在同尺寸下稳定
  function seeded(n) {
    const s = Math.sin(n * 127.1 + 311.7) * 43758.5453
    return s - Math.floor(s)
  }

  const LINK = 138

  // 二次贝塞尔取点：让信号严格沿弯曲的突触前进
  function quad(ax, ay, cx, cy, bx, by, t) {
    const u = 1 - t
    return [
      u * u * ax + 2 * u * t * cx + t * t * bx,
      u * u * ay + 2 * u * t * cy + t * t * by,
    ]
  }

  function step() {
    ctx.clearRect(0, 0, w, h)
    const t = perfNow() / 1000
    mouse.x += (mouse.tx - mouse.x) * 0.05
    mouse.y += (mouse.ty - mouse.y) * 0.05
    const px = (mouse.x - 0.5) * 26
    const py = (mouse.y - 0.5) * 26

    // 指针的 canvas 局部坐标:读缓存的 rect,只在 scroll/resize 标脏后才真正取
    let lx = -1e4, ly = -1e4
    if (!reduce && ptr.active) {
      ensureRect()
      lx = ptr.cx - rectLeft
      ly = ptr.cy - rectTop
    }

    for (const n of nodes) {
      if (!reduce) {
        n.x += n.vx; n.y += n.vy
        if (n.x < 0 || n.x > w) n.vx *= -1
        if (n.y < 0 || n.y > h) n.vy *= -1
        // 指针邻域:按距离蓄能(缓升缓降),并被轻微牵引
        const dxp = lx - (n.x + px), dyp = ly - (n.y + py)
        const dp = Math.hypot(dxp, dyp)
        const near = dp < FIELD_R ? 1 - dp / FIELD_R : 0
        n.e += (near - n.e) * (near > n.e ? 0.09 : 0.035)
        const pull = near * near * 15
        n.ox += ((dxp / (dp || 1)) * pull - n.ox) * 0.12
        n.oy += ((dyp / (dp || 1)) * pull - n.oy) * 0.12
        // 蓄满的节点自发放电:沿最近突触发一枚信号(每次越过阈值只发一枚)
        if (n.e > 0.55 && !n.fired && pulses.length < 10) {
          firePulse(n)
          n.fired = true
        } else if (n.e < 0.2) {
          n.fired = false
        }
      }
      // 有机呼吸：当前半径随各自相位缓慢起伏;蓄能再放大一点
      n.cr = n.r * (reduce ? 1 : (0.78 + 0.34 * Math.sin(t * n.breathe + n.phase)) * (1 + n.e * 0.7))
    }

    // 曲线突触：近邻之间画带轻微弧度的连接（比直线更有机）
    for (let i = 0; i < nodes.length; i++) {
      const a = nodes[i]
      for (let j = i + 1; j < nodes.length; j++) {
        const b = nodes[j]
        const dx = a.x - b.x, dy = a.y - b.y
        const d = Math.hypot(dx, dy)
        if (d < LINK) {
          // 指针邻域的突触随两端蓄能一起点亮
          const glow = Math.max(a.e, b.e)
          const o = Math.min(0.82, (1 - d / LINK) * 0.46 * (1 + glow * 1.3))
          // 控制点：垂直于连线方向偏移，符号由索引奇偶稳定，缓慢摆动
          const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2
          const nx = -dy / (d || 1), ny = dx / (d || 1)
          const bow = ((i + j) % 2 ? 1 : -1) * d * 0.14 * (reduce ? 1 : 0.7 + 0.3 * Math.sin(t * 0.6 + i))
          const cx = mx + nx * bow + px, cy = my + ny * bow + py
          ctx.strokeStyle = `rgba(56,220,196,${o})`
          ctx.lineWidth = 0.7 + glow * 0.5
          ctx.beginPath()
          ctx.moveTo(a.x + px + a.ox, a.y + py + a.oy)
          ctx.quadraticCurveTo(cx, cy, b.x + px + b.ox, b.y + py + b.oy)
          ctx.stroke()
        }
      }
    }

    // 节点（呼吸半径 + 极淡光晕;指针蓄能时更亮、光晕更大）
    for (const n of nodes) {
      const r = n.cr
      ctx.beginPath()
      ctx.arc(n.x + px + n.ox, n.y + py + n.oy, r, 0, Math.PI * 2)
      ctx.fillStyle = n.c
      ctx.globalAlpha = Math.min(1, 0.92 + n.e * 0.08)
      ctx.shadowColor = n.c
      ctx.shadowBlur = 8 + n.e * 16
      ctx.fill()
      ctx.shadowBlur = 0
      ctx.globalAlpha = 1
    }

    if (!reduce) {
      // 信号：偶发地沿某条弯曲突触传导，带一小段拖尾
      if (pulses.length < 6 && nodes.length > 2) {
        firePulse(nodes[(Math.floor(perfNow() / 200) + pulses.length) % nodes.length])
      }
      pulses = pulses.filter((p) => {
        p.t += 0.018
        if (p.t >= 1) return false
        const mx = (p.a.x + p.b.x) / 2, my = (p.a.y + p.b.y) / 2
        const cx = mx + p.nx * p.bow + px, cy = my + p.ny * p.bow + py
        // 拖尾：沿曲线取几个滞后点，越靠后越淡越小
        for (let k = 0; k < 5; k++) {
          const tt = p.t - k * 0.05
          if (tt < 0) break
          const [x, y] = quad(p.a.x + px + p.a.ox, p.a.y + py + p.a.oy, cx, cy, p.b.x + px + p.b.ox, p.b.y + py + p.b.oy, tt)
          const f = 1 - k / 5
          ctx.beginPath()
          ctx.arc(x, y, 2.4 * f, 0, Math.PI * 2)
          ctx.fillStyle = p.c
          ctx.globalAlpha = 0.85 * f
          ctx.shadowColor = p.c
          ctx.shadowBlur = 14 * f
          ctx.fill()
        }
        ctx.shadowBlur = 0
        ctx.globalAlpha = 1
        return true
      })

      // 涟漪:点击/轻点处荡开的青绿波纹,双圈错相,像水面轻叩
      ripples = ripples.filter((rp) => {
        rp.t += 0.016
        if (rp.t >= 1) return false
        const fade = (1 - rp.t) * (1 - rp.t)
        ctx.strokeStyle = `rgba(47,240,207,${(0.38 * fade).toFixed(3)})`
        ctx.lineWidth = 1.2
        ctx.beginPath()
        ctx.arc(rp.x, rp.y, 12 + rp.t * 200, 0, Math.PI * 2)
        ctx.stroke()
        if (rp.t > 0.14) {
          ctx.strokeStyle = `rgba(47,240,207,${(0.2 * fade).toFixed(3)})`
          ctx.beginPath()
          ctx.arc(rp.x, rp.y, 12 + (rp.t - 0.14) * 200, 0, Math.PI * 2)
          ctx.stroke()
        }
        return true
      })
    }
  }

  // rAF 收敛到单一 start/stop：running 标志保证任何时刻最多一条 rAF 链。
  // 原实现由 step() 自调度 + visibilitychange 里再拉一次，快速切标签页会叠出两条链 = 双倍功耗。
  function loop() {
    step()
    if (running) raf = requestAnimationFrame(loop)
  }
  function start() {
    if (running || reduce) return
    running = true
    raf = requestAnimationFrame(loop)
  }
  function stop() {
    running = false
    cancelAnimationFrame(raf)
    raf = 0
  }
  function sync() {
    if (inView && pageVisible) start()
    else stop()
  }

  // 从节点 a 沿最近突触发出一枚信号
  function firePulse(a) {
    const b = nearest(a)
    if (!b) return
    const dx = a.x - b.x, dy = a.y - b.y
    const d = Math.hypot(dx, dy) || 1
    pulses.push({ a, b, t: 0, c: a.c, bow: (a.x + a.y > b.x + b.y ? 1 : -1) * d * 0.14, nx: -dy / d, ny: dx / d })
  }

  function nearest(a) {
    let best = null, bd = LINK
    for (const n of nodes) {
      if (n === a) continue
      const d = Math.hypot(a.x - n.x, a.y - n.y)
      if (d < bd) { bd = d; best = n }
    }
    return best
  }

  // 用 performance.now 而非 Date.now / Math.random 驱动动画节奏
  function perfNow() {
    return (typeof performance !== 'undefined' ? performance.now() : 0)
  }

  function onMove(e) {
    mouse.tx = e.clientX / window.innerWidth
    mouse.ty = e.clientY / window.innerHeight
    ptr.cx = e.clientX
    ptr.cy = e.clientY
    ptr.active = true
  }

  // 点击/轻点:命中 canvas 范围内则荡开涟漪,并激发邻域节点放电
  function onDown(e) {
    const rect = canvas.getBoundingClientRect()
    const x = e.clientX - rect.left, y = e.clientY - rect.top
    if (x < 0 || y < 0 || x > rect.width || y > rect.height) return
    if (ripples.length >= 3) ripples.shift()
    ripples.push({ x, y, t: 0 })
    let shots = 0
    for (const n of nodes) {
      const d = Math.hypot(n.x - x, n.y - y)
      if (d < FIELD_R) {
        n.e = Math.min(1, n.e + (1 - d / FIELD_R) * 0.9)
        if (shots < 3 && pulses.length < 12) { firePulse(n); shots += 1 }
      }
    }
  }

  const ro = new ResizeObserver(resize)
  ro.observe(canvas)
  window.addEventListener('pointermove', onMove, { passive: true })
  // 滚动只改变 canvas 相对视口的位置，不改变尺寸(ResizeObserver 不会触发)，故单独标脏
  window.addEventListener('scroll', () => { rectDirty = true }, { passive: true })
  if (!reduce) {
    // 指针离开窗口:邻域效应缓缓衰退(reduce 下无动画循环,互动一律不挂)
    window.addEventListener('pointerout', (e) => { if (!e.relatedTarget) ptr.active = false })
    window.addEventListener('pointerdown', onDown, { passive: true })
  }
  resize()
  step() // 先画一帧：reduce 下这就是最终的静态画面；否则作为 loop 的起点

  // 滚出视口就停：Hero 神经场在页面下方看不见时不该继续满帧渲染
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) inView = e.isIntersecting
    sync()
  })
  io.observe(canvas)

  // 页面隐藏时暂停，省电
  document.addEventListener('visibilitychange', () => {
    pageVisible = !document.hidden
    sync()
  })

  sync()
}
