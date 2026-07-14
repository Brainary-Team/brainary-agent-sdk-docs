// 官网入口：自托管字体（本地打包，无 CDN）+ 样式 + 交互增强 + 中英双语。
import './style.css'

// 字体：@fontsource 由 Vite 打包本地 woff2（latin 子集，体积更小）。
import '@fontsource/sora/latin-600.css'
import '@fontsource/sora/latin-700.css'
import '@fontsource/sora/latin-800.css'
import '@fontsource/geist-sans/latin-400.css'
import '@fontsource/geist-sans/latin-500.css'
import '@fontsource/geist-sans/latin-600.css'
import '@fontsource/geist-mono/latin-400.css'
import '@fontsource/geist-mono/latin-500.css'

import { renderNav } from './partials/nav.js'
import { renderFooter } from './partials/footer.js'
import { initNeural } from './neural.js'
import { I18N, getLang, setLang, applyI18n } from './i18n.js'
import { site } from './config.js'

// ── 注入公共 chrome（nav / footer）────────────────────────
const navEl = document.getElementById('site-nav')
const footerEl = document.getElementById('site-footer')
if (navEl) renderNav(navEl)
if (footerEl) renderFooter(footerEl)

// ── 国际化：应用当前语言（partial 注入后执行，覆盖其中的 data-i18n）──
let lang = getLang()
applyI18n(lang)

const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

// ── Hero 打字机：轮播定位短语，跟随语言、可重启 ─────────
let twTimer = null
const typeEl = document.getElementById('typewriter')
function startTypewriter(l) {
  if (!typeEl) return
  if (twTimer) { clearTimeout(twTimer); twTimer = null }
  const phrases = (I18N[l] || I18N.zh)['hero.tw']
  if (reduceMotion) { typeEl.textContent = phrases[0]; return }
  let pi = 0, ci = 0, deleting = false
  const tick = () => {
    const word = phrases[pi]
    typeEl.textContent = word.slice(0, ci)
    if (!deleting && ci < word.length) { ci++; twTimer = setTimeout(tick, 120) }
    else if (!deleting && ci === word.length) { deleting = true; twTimer = setTimeout(tick, 1500) }
    else if (deleting && ci > 0) { ci--; twTimer = setTimeout(tick, 55) }
    else { deleting = false; pi = (pi + 1) % phrases.length; twTimer = setTimeout(tick, 320) }
  }
  tick()
}

// ── 语言切换按钮（中 ⇄ EN）─────────────────────────────
const langToggle = document.getElementById('lang-toggle')
function updateLangToggle(l) {
  if (!langToggle) return
  langToggle.textContent = l === 'zh' ? 'EN' : '中'
  langToggle.setAttribute('aria-label', l === 'zh' ? 'Switch to English' : '切换到中文')
}
updateLangToggle(lang)
langToggle?.addEventListener('click', () => {
  lang = lang === 'zh' ? 'en' : 'zh'
  setLang(lang)
  applyI18n(lang)
  updateLangToggle(lang)
  startTypewriter(lang)
})

// ── 导航：滚动加玻璃背板 + 移动端菜单 ────────────────────
if (navEl) {
  const onScroll = () => navEl.classList.toggle('nav-scrolled', window.scrollY > 12)
  onScroll()
  window.addEventListener('scroll', onScroll, { passive: true })

  const toggle = document.getElementById('nav-toggle')
  const menu = document.getElementById('nav-mobile')
  toggle?.addEventListener('click', () => {
    const open = menu.classList.toggle('hidden')
    toggle.setAttribute('aria-expanded', String(!open))
  })
  menu?.querySelectorAll('a').forEach((a) =>
    a.addEventListener('click', () => menu.classList.add('hidden'))
  )
}

// ── Hero self-trace 自省流:三幕场景,逐行浮现 + tab 切换 + 播完轮到下一幕 ──
// reduced-motion:当前幕整段静态直出、不轮播,tab 仍可切;document.hidden:暂停,回前台重播当前幕。
const tracePanel = document.getElementById('self-trace')
if (tracePanel) {
  const tabs = Array.from(tracePanel.querySelectorAll('.trace-tab'))
  const scenes = Array.from(tracePanel.querySelectorAll('.trace-scene'))
  let cur = 0

  const setActive = (idx) => {
    cur = idx
    tabs.forEach((t, i) => {
      t.classList.toggle('is-active', i === idx)
      t.setAttribute('aria-selected', String(i === idx))
    })
    scenes.forEach((s, i) => s.classList.toggle('is-active', i === idx))
  }

  if (reduceMotion) {
    // 所有行常亮;tab 只做即时切换,不播动画、不自动轮播
    scenes.forEach((s) => s.querySelectorAll('.trace-line').forEach((l) => l.classList.add('on')))
    tabs.forEach((t, i) => t.addEventListener('click', () => setActive(i)))
  } else {
    let timer = 0
    let started = false
    const play = () => {
      const lines = Array.from(scenes[cur].querySelectorAll('.trace-line'))
      let i = 0
      const stepLine = () => {
        if (i < lines.length) {
          lines[i].classList.add('on')
          i += 1
          // 下一行是自省行(◆)时多停一拍,像真的想了一下才开口
          const pause = i < lines.length && lines[i].classList.contains('t-reflect') ? 1250 : 900
          timer = setTimeout(stepLine, pause)
        } else {
          // 整幕读完:停留,然后自动轮到下一幕
          timer = setTimeout(() => switchTo((cur + 1) % scenes.length), 4600)
        }
      }
      stepLine()
    }
    const switchTo = (idx) => {
      clearTimeout(timer)
      started = true
      scenes.forEach((s) => s.querySelectorAll('.trace-line').forEach((l) => l.classList.remove('on')))
      setActive(idx)
      timer = setTimeout(play, 550)
    }
    tabs.forEach((t, i) => t.addEventListener('click', () => switchTo(i)))
    // tablist 键盘惯例:左右方向键在场景间移动
    tracePanel.querySelector('.trace-tabs')?.addEventListener('keydown', (e) => {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return
      const next = (cur + (e.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length
      switchTo(next)
      tabs[next].focus()
    })
    if ('IntersectionObserver' in window) {
      const io2 = new IntersectionObserver(
        (entries) => {
          if (entries.some((e) => e.isIntersecting)) {
            io2.disconnect()
            if (!started) { started = true; play() }
          }
        },
        { threshold: 0.25 }
      )
      io2.observe(tracePanel)
    } else {
      started = true
      play()
    }
    document.addEventListener('visibilitychange', () => {
      clearTimeout(timer)
      if (!document.hidden && started) switchTo(cur)
    })
  }
}

// ── 神经网络背景 ─────────────────────────────────────────
const canvas = document.getElementById('neural')
if (canvas) initNeural(canvas)

// ── 启动打字机 ───────────────────────────────────────────
startTypewriter(lang)

// 页面隐藏时暂停打字机,回到前台重启一轮(与 canvas / trace 同一节能纪律)
document.addEventListener('visibilitychange', () => {
  if (reduceMotion) return
  if (document.hidden) {
    if (twTimer) { clearTimeout(twTimer); twTimer = null }
  } else {
    startTypewriter(lang)
  }
})

// ── 滚动揭示 ─────────────────────────────────────────────
// 无 IntersectionObserver 时直接全部揭示,绝不白屏(构造必须在特性检测之后)
const revealEls = document.querySelectorAll('.reveal')
if (!('IntersectionObserver' in window)) {
  revealEls.forEach((el) => el.classList.add('in'))
} else {
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (e.isIntersecting) {
          e.target.classList.add('in')
          io.unobserve(e.target)
        }
      }
    },
    { threshold: 0.14 }
  )
  revealEls.forEach((el, i) => {
    el.style.animationDelay = `${(i % 6) * 90}ms`
    io.observe(el)
  })
}

// ── 一行命令安装：单一真源写入 + 复制到剪贴板 ───────────
// 命令文本以 config.cliInstallCmd 为准，覆盖 HTML 内联兜底串，全站各处安装框保持一致。
document.querySelectorAll('[data-install-cmd]').forEach((el) => {
  if (site.cliInstallCmd) el.textContent = site.cliInstallCmd
})

async function copyText(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text)
      return true
    }
  } catch (_) {}
  // 兜底：非安全上下文用临时 textarea + execCommand
  try {
    const ta = document.createElement('textarea')
    ta.value = text
    ta.setAttribute('readonly', '')
    ta.style.position = 'fixed'
    ta.style.opacity = '0'
    document.body.appendChild(ta)
    ta.select()
    const ok = document.execCommand('copy')
    document.body.removeChild(ta)
    return ok
  } catch (_) {
    return false
  }
}

// 事件委托：任意安装框内的复制按钮都生效（hero / 快捷入口 / CTA 共用同一逻辑）
document.addEventListener('click', async (e) => {
  const btn = e.target.closest('.install-copy')
  if (!btn) return
  const box = btn.closest('.install-box')
  const cmd = box?.querySelector('[data-install-cmd]')?.textContent?.trim()
  if (!cmd) return
  const ok = await copyText(cmd)
  if (!ok) return
  const label = btn.querySelector('.install-copy-label')
  const dict = I18N[lang] || I18N.zh
  btn.classList.add('copied')
  if (label) label.textContent = dict['install.copied']
  clearTimeout(btn._copiedTimer)
  btn._copiedTimer = setTimeout(() => {
    btn.classList.remove('copied')
    if (label) label.textContent = (I18N[lang] || I18N.zh)['install.copy']
  }, 1800)
})

// 年份兜底（若模板里有占位）
document.querySelectorAll('[data-year]').forEach((el) => (el.textContent = '2026'))
