// 可复用导航栏 partial：注入到 <header id="site-nav">。
// 多页扩展时各页复用同一函数，避免拷贝导航结构（方案 5.1 组件化要求）。
import { site, navLinks } from '../config.js'

const brandMark = `
  <a href="#top" class="flex items-center gap-2.5 group" aria-label="返回 Brainary 首页" data-i18n-aria="a11y.brandHome">
    <span class="relative grid place-items-center w-9 h-9 rounded-lg glass overflow-hidden">
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" aria-hidden="true">
        <circle cx="12" cy="12" r="2.4" fill="var(--color-teal)"/>
        <circle cx="5" cy="6" r="1.5" fill="var(--color-mint)"/>
        <circle cx="19" cy="7" r="1.5" fill="var(--color-deep-teal)"/>
        <circle cx="6" cy="18" r="1.5" fill="var(--color-teal)"/>
        <circle cx="18" cy="17" r="1.5" fill="var(--color-mint)"/>
        <g stroke="var(--color-teal)" stroke-width="0.9" opacity="0.65">
          <line x1="12" y1="12" x2="5" y2="6"/><line x1="12" y1="12" x2="19" y2="7"/>
          <line x1="12" y1="12" x2="6" y2="18"/><line x1="12" y1="12" x2="18" y2="17"/>
        </g>
      </svg>
    </span>
    <span class="font-display font-bold text-lg tracking-tight">Brainary</span>
  </a>`

const linkHtml = (l) => {
  const soon = l.soon
    ? `<span class="ml-1.5 align-middle text-[0.6rem] font-mono tracking-widest text-[var(--color-faint)]">SOON</span>`
    : ''
  // external（如 SDK 文档 /docs/）在新标签页打开、保留官网页；rel=noopener 防 tab-nabbing。
  const target = l.external ? ' target="_blank" rel="noopener"' : ''
  // soon 项（如 Code SDK）尚未上线：标 data-soon，点击由 main.js 拦截并弹「即将上线」提示，而非跳死链。
  const soonAttr = l.soon ? ' data-soon aria-disabled="true"' : ''
  return `<a href="${l.href}"${target}${soonAttr}
      class="text-sm text-[var(--color-mist)] hover:text-[var(--color-ink)] transition-colors"><span data-i18n="nav.${l.key}">${l.label}</span>${soon}</a>`
}

export function renderNav(el) {
  el.className = 'fixed top-0 inset-x-0 z-50 transition-all duration-300'
  el.innerHTML = `
    <nav class="max-w-6xl mx-auto px-5 sm:px-8 h-16 flex items-center justify-between">
      ${brandMark}
      <div class="hidden md:flex items-center gap-8">
        ${navLinks.map(linkHtml).join('')}
      </div>
      <div class="flex items-center gap-3">
        <button id="lang-toggle" class="grid place-items-center h-9 min-w-9 px-2.5 rounded-lg glass font-mono text-xs tracking-wider text-[var(--color-mist)] hover:text-[var(--color-ink)] transition-colors" aria-label="Switch language">EN</button>
        <button id="nav-toggle" class="md:hidden grid place-items-center w-9 h-9 rounded-lg glass" aria-label="展开菜单" data-i18n-aria="a11y.menu" aria-expanded="false">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>
        </button>
      </div>
    </nav>
    <div id="nav-mobile" class="md:hidden hidden px-5 pb-4">
      <div class="glass rounded-xl p-4 flex flex-col gap-3">
        ${navLinks.map(linkHtml).join('')}
      </div>
    </div>`
}
