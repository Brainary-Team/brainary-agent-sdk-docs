// 站点国际化：中英双语。单一字典驱动全站文案 + 打字机短语 + <title>/<meta>。
// 用法：元素挂 data-i18n="key"，applyI18n(lang) 用 innerHTML 覆盖（值可含内联标记）。
// 兜底：index.html / partial 内联中文即无-JS 兜底；有 JS 时 applyI18n 按所选语言覆盖。

export const I18N = {
  zh: {
    'meta.title': 'Brainary · 会自我进化的元认知智能体 | 领智智能',
    'meta.desc':
      'Brainary（领智智能）—— 具备元认知、自我认知与自我进化能力的智能体。召之即来，从编码到日常工作、辅助思考与数字分身。',

    // 导航
    'nav.home': '首页',
    'nav.capabilities': '能力',
    'nav.sdk': 'SDK 文档',
    'nav.code': 'Code SDK',
    'nav.cliBtn': '下载 CLI',

    // Hero
    'hero.pill': 'METACOGNITIVE AGENT',
    'hero.badge': 'v0 · 预览',
    'hero.lead1': '一个会',
    'hero.lead2': '的智能体',
    'hero.tw': ['自我认知', '元认知推理', '自我进化', '仿生架构'],
    'hero.para':
      '一个召之即来的智能体，却不止于编码 —— 它替你写代码、打理日常工作、陪你思考，乃至成为你的数字分身。底层是仿生的元认知内核：<span class="font-mono text-[var(--color-ink)]">会审视自己的推理</span>、从经验中沉淀能力，越用越懂你。',
    'hero.btnDownload': '下载 Brainary CLI',
    'hero.btnDocs': '查看 SDK 文档',
    'hero.t1': '编码 · 日常 · 思考 · 分身',
    'hero.t2': '元认知 · 自我进化',
    'hero.t3': '记忆 · 工具 · 自省闭环',

    // Hero self-trace 自省流(签名元素;DEMO 示意,不代表真实数据)
    // 三个场景:s1 编码自审 / s2 会议纪要 / s3 流程蒸馏;tab 可切,播完自动轮到下一幕
    'trace.title': 'brainary · self-trace',
    'trace.tag': 'DEMO 示意',
    'trace.tab1': '编码自审',
    'trace.tab2': '会议纪要',
    'trace.tab3': '流程蒸馏',
    'trace.s1.l1': '任务:实现登录限流中间件,附带测试',
    'trace.s1.l2': '规划 4 步 · 检索代码库记忆 ×1',
    'trace.s1.l3': '步骤 1 — 写出中间件 + 单元测试',
    'trace.s1.l4': '自省:同秒并发请求会漏计 —— 边界没盖住',
    'trace.s1.l5': '步骤 2 — 补上竞态用例,修正计数逻辑',
    'trace.s1.l6': '元认知:「先写后审」这套打法值得固化',
    'trace.s1.l7': '技能已沉淀:code-selfcheck · 下次直接调用',
    'trace.s2.l1': '任务:整理本周会议纪要,产出待办清单',
    'trace.s2.l2': '规划 3 步 · 调用长期记忆 ×2',
    'trace.s2.l3': '步骤 1 — 提取各场会议要点',
    'trace.s2.l4': '自省:证据还不足,先回读原文再下结论',
    'trace.s2.l5': '步骤 2 — 交叉核对,修正 1 处结论',
    'trace.s2.l6': '元认知:这套流程可复用 → 沉淀为技能',
    'trace.s2.l7': '技能已沉淀:meeting-digest · 下次直接调用',
    'trace.s3.l1': '任务:汇总数据周报 —— 已是第 3 次做',
    'trace.s3.l2': '检索情景记忆 · 命中相似轨迹 ×2',
    'trace.s3.l3': '自省:同样的步骤重复 3 遍,该蒸馏了',
    'trace.s3.l4': '步骤 1 — 对齐三次轨迹,抽出稳定骨架',
    'trace.s3.l5': '步骤 2 — 参数化差异项,生成技能模板',
    'trace.s3.l6': '元认知:同类任务以后跳过规划,直接调用',
    'trace.s3.l7': '技能已沉淀:weekly-report · 已入技能库',

    // 能力
    'cap.eyebrow': '核心能力',
    'cap.title':
      '不只是调用模型，<br class="hidden sm:block" />而是<span class="text-gradient">会思考自己</span>的智能体',
    'cap.c1.title': '元认知',
    'cap.c1.desc':
      '审视自己的推理过程，知道自己知道什么、不知道什么，并据此调整策略 —— 一个会回看自身思维的系统。',
    'cap.c2.title': '自我进化',
    'cap.c2.desc': '从交互与经验中沉淀可复用能力，越用越强，无需每次从零开始。',
    'cap.c3.title': '仿生架构',
    'cap.c3.desc': '感知—记忆—决策—行动的类脑闭环，让能力像器官一样可组合、可协作。',
    'cap.c4.title': '多种身位',
    'cap.c4.desc':
      '从编码到日常工作、辅助思考，乃至你的<span class="font-mono text-[var(--color-ink)]">数字分身</span> —— 同一个会进化的元认知内核，换一副身位继续懂你。',

    // 快捷入口
    'entry.eyebrow': '快捷入口',
    'entry.title': '从这里开始',
    'entry.cli.tag': '占位',
    'entry.cli.title': '下载 Brainary CLI',
    'entry.cli.desc': '获取命令行工具，本地跑通第一个智能体。二进制包即将提供。',
    'entry.cli.cta': '获取 CLI',
    'entry.sdk.tag': '已上线',
    'entry.sdk.title': 'SDK 文档',
    'entry.sdk.desc': 'brainary-sdk 的完整用户文档：入口、Options、消息模型、工具与 primitive。',
    'entry.sdk.cta': '进入文档',
    'entry.code.tag': 'SOON',
    'entry.code.title': 'Code SDK 文档',
    'entry.code.desc': '面向编码场景的 Brainary Code 产品文档，正在打磨，敬请期待。',
    'entry.code.cta': '即将上线',

    // CTA
    'cta.title': '一个会思考自己的智能体，替你做事',
    'cta.desc':
      '从写代码到打理日常、辅助思考与数字分身 —— Brainary 会自省、会进化，越用越懂你。',
    'cta.btnDownload': '下载 Brainary CLI',
    'cta.btnDocs': '查看 SDK 文档',

    // 页脚
    'footer.tagline':
      '具备元认知与自我进化能力的智能体 —— 从编码到日常、思考与数字分身，召之即来，越用越懂你。',
    'footer.demoTag': 'DEMO · 占位演示站',
    'footer.colProduct': '产品',
    'footer.cli': '下载 CLI',
    'footer.sdk': 'SDK 文档',
    'footer.code': 'Code SDK',
    'footer.colCompany': '公司',
    'footer.about': '关于',
    'footer.contact': '联系',
    'footer.copyright': '© 2026 领智智能（Brainary）· 保留所有权利',
    'footer.mono': 'metacognitive · self-evolving · bionic',

    // 无障碍标签(aria-label,经 data-i18n-aria 应用)
    'a11y.brandHome': '返回 Brainary 首页',
    'a11y.menu': '展开菜单',
    'a11y.trace': 'Brainary self-trace 自省流示意面板',
    'a11y.traceTabs': '切换自省流示例场景',
  },

  en: {
    'meta.title': 'Brainary · A self-evolving, metacognitive agent',
    'meta.desc':
      'Brainary — an agent with metacognition, self-awareness and self-evolution. Summon it on demand, from coding to daily work, thinking support and your digital twin.',

    // Nav
    'nav.home': 'Home',
    'nav.capabilities': 'Capabilities',
    'nav.sdk': 'SDK Docs',
    'nav.code': 'Code SDK',
    'nav.cliBtn': 'Download CLI',

    // Hero
    'hero.pill': 'METACOGNITIVE AGENT',
    'hero.badge': 'v0 · Preview',
    'hero.lead1': 'An agent that',
    'hero.lead2': '',
    'hero.tw': ['knows itself', 'reasons about reasoning', 'evolves with use', 'thinks like a brain'],
    'hero.para':
      'An agent you summon on demand — and it goes beyond coding. It writes your code, handles daily work, thinks alongside you, even becomes your digital twin. Underneath is a bionic metacognitive core that <span class="font-mono text-[var(--color-ink)]">examines its own reasoning</span>, distills skill from experience, and understands you more the more you use it.',
    'hero.btnDownload': 'Download Brainary CLI',
    'hero.btnDocs': 'View SDK Docs',
    'hero.t1': 'Coding · Work · Thinking · Twin',
    'hero.t2': 'Metacognition · Self-evolution',
    'hero.t3': 'Memory · Tools · Self-reflection loop',

    // Hero self-trace stream (signature element; illustrative demo, not real data)
    // Three scenes: s1 code + self-review / s2 meeting digest / s3 workflow distillation
    'trace.title': 'brainary · self-trace',
    'trace.tag': 'DEMO',
    'trace.tab1': 'coding',
    'trace.tab2': 'meetings',
    'trace.tab3': 'distill',
    'trace.s1.l1': 'task: build rate-limit middleware, with tests',
    'trace.s1.l2': 'plan: 4 steps · codebase memory ×1',
    'trace.s1.l3': 'step 1 — write middleware + unit tests',
    'trace.s1.l4': 'reflect: same-second bursts slip past — edge uncovered',
    'trace.s1.l5': 'step 2 — add a race case, fix the counting',
    'trace.s1.l6': 'metacognition: write-then-audit is worth keeping',
    'trace.s1.l7': 'skill saved: code-selfcheck · reused next time',
    'trace.s2.l1': 'task: digest this week’s meetings → todos',
    'trace.s2.l2': 'plan: 3 steps · long-term memory ×2',
    'trace.s2.l3': 'step 1 — extract key points per meeting',
    'trace.s2.l4': 'reflect: evidence is thin — reread the source first',
    'trace.s2.l5': 'step 2 — cross-check, revise 1 conclusion',
    'trace.s2.l6': 'metacognition: this flow is reusable → distill a skill',
    'trace.s2.l7': 'skill saved: meeting-digest · reused next time',
    'trace.s3.l1': 'task: compile the weekly report — 3rd time now',
    'trace.s3.l2': 'episodic memory · 2 similar traces matched',
    'trace.s3.l3': 'reflect: same steps three times — time to distill',
    'trace.s3.l4': 'step 1 — align the traces, extract the stable core',
    'trace.s3.l5': 'step 2 — parameterize deltas into a template',
    'trace.s3.l6': 'metacognition: skip planning next time, just call it',
    'trace.s3.l7': 'skill saved: weekly-report · in the library',

    // Capabilities
    'cap.eyebrow': 'Core Capabilities',
    'cap.title':
      'Not just calling a model —<br class="hidden sm:block" />an agent that <span class="text-gradient">thinks about itself</span>',
    'cap.c1.title': 'Metacognition',
    'cap.c1.desc':
      'It watches its own reasoning — aware of what it does and does not know — and adjusts strategy accordingly. A system that looks back on its own thinking.',
    'cap.c2.title': 'Self-evolution',
    'cap.c2.desc':
      'It distills reusable skills from interaction and experience — stronger the more you use it, never starting from scratch.',
    'cap.c3.title': 'Bionic architecture',
    'cap.c3.desc':
      'A brain-like perceive–remember–decide–act loop, where capabilities compose and cooperate like organs.',
    'cap.c4.title': 'Many roles',
    'cap.c4.desc':
      'From coding to daily work and thinking support, even your <span class="font-mono text-[var(--color-ink)]">digital twin</span> — one evolving metacognitive core, shifting roles while still knowing you.',

    // Quick start
    'entry.eyebrow': 'Quick Start',
    'entry.title': 'Start here',
    'entry.cli.tag': 'Placeholder',
    'entry.cli.title': 'Download Brainary CLI',
    'entry.cli.desc': 'Get the CLI and run your first agent locally. Binaries coming soon.',
    'entry.cli.cta': 'Get the CLI',
    'entry.sdk.tag': 'Live',
    'entry.sdk.title': 'SDK Docs',
    'entry.sdk.desc':
      'Full brainary-sdk docs: entry points, Options, the message model, tools and primitives.',
    'entry.sdk.cta': 'Open docs',
    'entry.code.tag': 'SOON',
    'entry.code.title': 'Code SDK Docs',
    'entry.code.desc':
      'Docs for Brainary Code, the coding-focused product — in the works, stay tuned.',
    'entry.code.cta': 'Coming soon',

    // CTA
    'cta.title': 'An agent that thinks about itself — working for you',
    'cta.desc':
      'From writing code to daily work, thinking support and a digital twin — Brainary reflects, evolves, and understands you more over time.',
    'cta.btnDownload': 'Download Brainary CLI',
    'cta.btnDocs': 'View SDK Docs',

    // Footer
    'footer.tagline':
      'An agent with metacognition and self-evolution — from coding to daily work, thinking and a digital twin. Summon it on demand; it understands you more over time.',
    'footer.demoTag': 'DEMO · Placeholder site',
    'footer.colProduct': 'Product',
    'footer.cli': 'Download CLI',
    'footer.sdk': 'SDK Docs',
    'footer.code': 'Code SDK',
    'footer.colCompany': 'Company',
    'footer.about': 'About',
    'footer.contact': 'Contact',
    'footer.copyright': '© 2026 Lingzhi AI (Brainary) · All rights reserved',
    'footer.mono': 'metacognitive · self-evolving · bionic',

    // Accessibility labels (aria-label, applied via data-i18n-aria)
    'a11y.brandHome': 'Back to Brainary home',
    'a11y.menu': 'Open menu',
    'a11y.trace': 'Brainary self-trace demo panel',
    'a11y.traceTabs': 'Switch self-trace example scene',
  },
}

const STORE_KEY = 'brainary-lang'

// 当前语言：localStorage > 浏览器语言 > 默认 zh
export function getLang() {
  try {
    const saved = localStorage.getItem(STORE_KEY)
    if (saved === 'zh' || saved === 'en') return saved
  } catch (_) {}
  const nav = (navigator.language || 'zh').toLowerCase()
  return nav.startsWith('zh') ? 'zh' : 'en'
}

export function setLang(lang) {
  try {
    localStorage.setItem(STORE_KEY, lang)
  } catch (_) {}
}

// 覆盖所有 [data-i18n] 文本 + [data-i18n-aria] 的 aria-label
// + 同步 <title>/<meta description>/<html lang>
export function applyI18n(lang, root = document) {
  const dict = I18N[lang] || I18N.zh
  root.querySelectorAll('[data-i18n]').forEach((el) => {
    const k = el.getAttribute('data-i18n')
    const v = dict[k]
    if (typeof v === 'string') el.innerHTML = v
  })
  root.querySelectorAll('[data-i18n-aria]').forEach((el) => {
    const v = dict[el.getAttribute('data-i18n-aria')]
    if (typeof v === 'string') el.setAttribute('aria-label', v)
  })
  if (root === document) {
    if (dict['meta.title']) document.title = dict['meta.title']
    const md = document.querySelector('meta[name="description"]')
    if (md && dict['meta.desc']) md.setAttribute('content', dict['meta.desc'])
    document.documentElement.lang = lang === 'en' ? 'en' : 'zh-CN'
  }
}
