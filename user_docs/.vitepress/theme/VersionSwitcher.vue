<script setup lang="ts">
// 文档版本切换器（Python 式）。核心约束：
//   · 每个版本是独立冻结的静态构建，部署在 /docs/<ver>/ 下。旧版永不重建。
//   · 版本列表来自「运行时」拉取的 /docs/versions.json（唯一可变文件），因此
//     一个已冻结的旧版页面也能列出后来发布的新版本 —— 这正是冻结模型能工作的关键。
//
// UI：不用原生 <select>（macOS 下渲染成蓝色系统药丸、且 <option> 列表无法用 CSS 定制，
// 与 VitePress 顶栏割裂）。改为「触发按钮 + 自定义弹层菜单」，全部用 VitePress 主题变量
// 上色 → light/dark 自动跟随、与顶栏一致。
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { inBrowser } from 'vitepress'

// 由 config.mts 的 vite.define 编译期注入 = `<SITE_BASE>docs/`（根部署为 '/docs/'，
// GitHub Pages 子路径为 '/brainary-docs/docs/'）。使切换器对部署基路径自适应。
declare const __DOCS_ROOT__: string

interface VersionEntry {
  version: string // URL 段：预 tag 阶段是 brainary-rs 短 hash，正式 tag 后可为 semver
  label: string // 下拉显示文案，如 `rs@9541095 · 2026-07-06 (latest)`
  stable?: boolean
  commit?: string // 关联的 brainary-rs 完整 40 位 commit（溯源用，展示在 tooltip）
  date?: string // 该 commit 的提交日期 YYYY-MM-DD
  ref?: string // 派生所用的 git ref，如 origin/master
}

// 全站文档根前缀（编译期注入，随部署基路径变化）。所有版本挂在它下面：
// <root><ver>/... 、清单在 <root>versions.json。
const DOCS_ROOT = __DOCS_ROOT__
// 默认落地页（Python 优先，与顶栏一致）；切版本缺页时的兜底目标。
const DEFAULT_SUBPATH = 'sdk-py/overview.html'

const versions = ref<VersionEntry[]>([])
const current = ref<string>('') // 当前版本段；dev（无版本段）时对齐到 latest
const ready = ref(false)
const open = ref(false)
const root = ref<HTMLElement | null>(null)

// 当前版本对应的显示标签（找不到就退回裸版本号）。
const currentLabel = computed(() => {
  const hit = versions.value.find((v) => v.version === current.value)
  return hit ? hit.label : current.value
})

// 当前版本对应的完整条目（用于 trigger 的 commit/date 溯源 tooltip）。
const currentEntry = computed(() => versions.value.find((v) => v.version === current.value) || null)
const currentTitle = computed(() => {
  const e = currentEntry.value
  if (!e) return '切换文档版本'
  const parts: string[] = []
  if (e.ref) parts.push(e.ref)
  if (e.commit) parts.push(`brainary-rs @ ${e.commit}`)
  if (e.date) parts.push(e.date)
  return parts.length ? parts.join('\n') : '切换文档版本'
})

// 从 /docs/<ver>/sdk-py/options.html 解析出 [版本段, 语言相对子路径]。
// 版本段的判定「清单驱动」：首段命中已知版本列表才算版本段，否则视为 dev（无版本段）。
// 这样对任意版本命名（brainary-rs 短 hash / 未来 semver）都成立，零格式假设。
// dev base 为 /docs/（无版本段）时，返回 ['', 子路径]。
function parsePath(pathname: string, knownVersions: string[]): [string, string] {
  if (!pathname.startsWith(DOCS_ROOT)) return ['', DEFAULT_SUBPATH]
  const rest = pathname.slice(DOCS_ROOT.length) // '<ver>/sdk-py/options.html' 或 'sdk-py/...'（dev）
  const slash = rest.indexOf('/')
  const first = slash < 0 ? rest : rest.slice(0, slash)
  const tail = slash < 0 ? '' : rest.slice(slash + 1)
  if (knownVersions.includes(first)) return [first, tail || DEFAULT_SUBPATH]
  return ['', rest || DEFAULT_SUBPATH] // dev：整段即语言相对子路径
}

async function selectVersion(newVer: string) {
  open.value = false
  if (!newVer || newVer === current.value) return
  const [, subpath] = parsePath(location.pathname, versions.value.map((v) => v.version))
  const target = `${DOCS_ROOT}${newVer}/${subpath}`
  // 目标页可能在该版本不存在（新增/删除页）→ HEAD 探一下，缺页回退该版默认页。
  let dest = target
  try {
    const probe = await fetch(target, { method: 'HEAD' })
    if (!probe.ok) dest = `${DOCS_ROOT}${newVer}/${DEFAULT_SUBPATH}`
  } catch {
    dest = `${DOCS_ROOT}${newVer}/${DEFAULT_SUBPATH}`
  }
  // 跨独立构建：必须整页刷新，不能用 SPA 路由（router.go 无法跨越另一次 build）。
  location.href = dest
}

function toggle() {
  open.value = !open.value
}

// 点击组件外 / 按 Esc → 关闭弹层。
function onDocClick(e: MouseEvent) {
  if (root.value && !root.value.contains(e.target as Node)) open.value = false
}
function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') open.value = false
}

onMounted(async () => {
  if (!inBrowser) return
  document.addEventListener('click', onDocClick)
  document.addEventListener('keydown', onKeydown)
  try {
    // ⚠ 坑：清单在文档根，绝不能用 withBase('/versions.json') —— 那会得到
    //   /docs/<ver>/versions.json（404）。这里用站点根绝对 URL 直取。
    // 必须「先」拿到清单：版本段的判定是清单驱动的（见 parsePath）。
    const url = new URL(`${DOCS_ROOT}versions.json`, location.origin).href
    const res = await fetch(url, { cache: 'no-cache' })
    if (res.ok) {
      const data = await res.json()
      versions.value = Array.isArray(data?.versions) ? data.versions : []
      const [ver] = parsePath(location.pathname, versions.value.map((v) => v.version))
      // dev（无版本段）时，把当前项对齐到 latest，避免标签为空。
      current.value = ver || data?.latest || ''
      ready.value = versions.value.length > 0
    }
  } catch {
    // 清单缺失（如纯 dev 直跑、未 build）→ 静默降级，不渲染切换器。
    ready.value = false
  }
})

onUnmounted(() => {
  if (!inBrowser) return
  document.removeEventListener('click', onDocClick)
  document.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <div v-if="ready" ref="root" class="version-switcher">
    <button
      class="vs-trigger"
      type="button"
      :aria-expanded="open"
      aria-haspopup="listbox"
      aria-label="切换文档版本"
      :title="currentTitle"
      @click="toggle"
    >
      <span class="vs-label">{{ currentLabel }}</span>
      <span class="vs-caret" :class="{ open }" aria-hidden="true">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M6 9l6 6 6-6" />
        </svg>
      </span>
    </button>

    <div v-show="open" class="vs-menu" role="listbox">
      <button
        v-for="v in versions"
        :key="v.version"
        class="vs-item"
        :class="{ active: v.version === current }"
        role="option"
        :aria-selected="v.version === current"
        type="button"
        @click="selectVersion(v.version)"
      >
        <span class="vs-check" aria-hidden="true">
          <svg
            v-if="v.version === current"
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
          >
            <path d="M20 6L9 17l-5-5" />
          </svg>
        </span>
        <span class="vs-item-label">{{ v.label }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.version-switcher {
  position: relative;
  display: flex;
  align-items: center;
  /* 与右侧 Search 框、左侧站点标题都留出间距，避免贴死。 */
  margin: 0 16px 0 8px;
}

/* 触发按钮：贴合 VitePress 顶栏文字风格，hover 变品牌色。 */
.vs-trigger {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  height: 34px;
  padding: 0 6px 0 12px;
  font-size: 13px;
  font-weight: 500;
  line-height: 1;
  color: var(--vp-c-text-1);
  background: transparent;
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  cursor: pointer;
  white-space: nowrap;
  transition: border-color 0.25s, color 0.25s;
}
.vs-trigger:hover {
  color: var(--vp-c-brand-1);
  border-color: var(--vp-c-brand-1);
}
.vs-caret {
  display: inline-flex;
  color: var(--vp-c-text-3);
  transition: transform 0.25s, color 0.25s;
}
.vs-caret.open {
  transform: rotate(180deg);
}
.vs-trigger:hover .vs-caret {
  color: var(--vp-c-brand-1);
}

/* 弹层菜单：VitePress 卡片风（bg + divider + 阴影），与主题面板一致。 */
.vs-menu {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  min-width: 168px;
  padding: 6px;
  background: var(--vp-c-bg-elv);
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  box-shadow: var(--vp-shadow-3);
  z-index: 100;
}
.vs-item {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
  padding: 6px 10px;
  font-size: 13px;
  line-height: 1.4;
  text-align: left;
  color: var(--vp-c-text-1);
  background: transparent;
  border: 0;
  border-radius: 6px;
  cursor: pointer;
  white-space: nowrap;
  transition: background-color 0.25s, color 0.25s;
}
.vs-item:hover {
  background: var(--vp-c-default-soft);
}
.vs-item.active {
  color: var(--vp-c-brand-1);
  font-weight: 600;
}
.vs-check {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 14px;
  flex: none;
  color: var(--vp-c-brand-1);
}
</style>
