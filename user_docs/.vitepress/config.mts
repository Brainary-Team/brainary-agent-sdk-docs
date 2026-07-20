import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

// dev 期单源代理下的 HMR 修正（仅当 start-docs.sh 整站启动时设该变量；standalone / build 不受影响）：
//   文档经官网源 /docs/ 打开后，VitePress 自带的 Vite HMR websocket 会和官网 Vite 的 HMR
//   撞在同一源 → 文档热更新失效/报错。这里让文档 HMR 的 ws 直连自己的端口（本机可达），
//   绕开代理与冲突。未设 DOCS_HMR_CLIENT_PORT 时不注入 vite 字段，行为完全不变。
const docsHmrClientPort = process.env.DOCS_HMR_CLIENT_PORT

// dev 文件监听排除（始终生效，含 standalone `vitepress dev`）：
//   冻结产物 .versions/ 与构建输出 .vitepress/dist/、缓存 .vitepress/cache/ 都在
//   user_docs/ 内，落在 VitePress 的监听树里。跑 ./snapshot.sh（内部 docs:build）或任何
//   构建会往这些目录写入几百个 HTML → dev 的 chokidar 监听触发海量 page reload，把 dev
//   server 冲垮/拖死（现象：官网 /docs/ 反代无上游 → 502）。这里显式忽略，杜绝复发。
const watchIgnored = ['**/.versions/**', '**/.vitepress/dist/**', '**/.vitepress/cache/**']

// 全站部署基路径（GitHub Pages 项目页在子路径，见 deploy.env 的 SITE_BASE；自定义域名/根部署为 /）。
// 由 snapshot.sh 发版时经 SITE_BASE 传入；未设则 '/'（本地 dev / 根部署）。首尾必带 '/'。
// 文档根 = <SITE_BASE>docs/。把它编译期注入 __DOCS_ROOT__，供 VersionSwitcher 运行时拼
// 清单地址与跨版本目标——从而切换器对根/子路径自适应，无任何硬编码 '/docs/'。
const siteBase = process.env.SITE_BASE || '/'
const docsRoot = `${siteBase}docs/`

// vite 覆盖分两层：
//   · define.__DOCS_ROOT__ —— build 与 dev 都需要（编译期常量），始终生效。
//   · server.watch/hmr    —— 仅 dev server（监听排除 + 单源代理 HMR 直连），build 无影响。
const viteOverride = {
  vite: {
    define: { __DOCS_ROOT__: JSON.stringify(docsRoot) },
    server: {
      watch: { ignored: watchIgnored },
      ...(docsHmrClientPort
        ? { hmr: { clientPort: Number(docsHmrClientPort), host: '127.0.0.1', protocol: 'ws' as const } }
        : {}),
    },
  },
}

// Brainary 面向 SDK 使用者的中文公开文档站配置
// 对客户交付：只保留 brainary-agent-sdk 两个门面模块
//   Rust（/sdk/**） · Python（/sdk-py/**）
// 约定：sidebar 每个 link 必对应真实 .md 文件，否则 docs:build 报 dead link
// Mermaid：架构图用 ```mermaid 代码块，由 withMermaid 渲染
//
// 版本切换（Python 式冻结快照，见 snapshot.sh / VersionSwitcher.vue）：
//   base 按 DOCS_VERSION 参数化 → 发版构建产物落在 /docs/<ver>/ 下。VitePress
//   在「构建时」给所有根绝对链接（/sdk/x）自动加 base 前缀，故切版本无需改任何链接。
//   版本段（<ver>）此处不作格式假设：预 tag 阶段是 brainary-rs 提交短 hash
//   （如 9541095，snapshot.sh 自动派生），正式 tag 后可为 semver（如 1.0）。
//   下拉框对「首段是不是版本段」的判定是清单驱动的（见 VersionSwitcher.parsePath），
//   与段的具体命名解耦，故这里改版本命名无需动任何解析代码。
//   ⚠ 作者纪律：markdown 内部链接一律写根绝对且不含版本（/sdk/… 、/sdk-py/…），
//     绝不写死 /docs/… 或 /docs/<ver>/…，否则会绕过 base 注入、跨版本失效。
const versionSeg = process.env.DOCS_VERSION

export default withMermaid(defineConfig({
  title: 'brainary-agent-sdk',
  description: '用 Python / Rust 构建 LLM Agent 的门面 SDK',
  lang: 'zh-CN',
  lastUpdated: true,

  // 与官网分层：官网占 <SITE_BASE>（website/），文档整体挂到 <SITE_BASE>docs/（方案 4.1 / 4.2）。
  // 效果：所有内部链接与静态资源自动加该前缀，原主页变为 <SITE_BASE>docs/，内容零改动。
  // 发版：SITE_BASE=/brainary-agent-sdk-docs/ DOCS_VERSION=3caa334 → base '/brainary-agent-sdk-docs/docs/3caa334/'。
  // dev / 未设：SITE_BASE='/' → '/docs/'（start-docs.sh 已同步打开该路径，代理零改动）。
  base: `${siteBase}docs/${versionSeg ? `${versionSeg}/` : ''}`,

  // Mermaid 标签显示修正：mermaid 把标签放进「固定高度」的 <foreignObject>，
  // 高度按 line-height:1.5、段落无外边距 测量。但 VitePress 默认主题的
  // `.vp-doc p { margin:16px 0 }` 会渗进 SVG 标签的 <p>，多出约 32px 撑破固定
  // 高度 → 多行节点上下两行被裁。这里清零段内外边距、并给 foreignObject 开
  // overflow 兜底。用 head 内联样式而非自定义 theme，避免干扰 mermaid 组件注册。
  head: [
    [
      'style',
      {},
      '.vp-doc .mermaid p{margin:0}' +
        '.vp-doc .mermaid .nodeLabel,.vp-doc .mermaid .edgeLabel{line-height:1.5}' +
        '.vp-doc .mermaid foreignObject{overflow:visible}',
    ],
  ],

  themeConfig: {
    // 产品名在左上角站点标题（title）承载；右上角只放语言切换，直接平铺
    // Python / Rust（Python 在前为默认）。
    nav: [
      { text: 'Python', link: '/sdk-py/overview', activeMatch: '/sdk-py/' },
      { text: 'Rust', link: '/sdk/overview', activeMatch: '/sdk/' },
    ],

    sidebar: {
      '/sdk/': [
        {
          text: '入门与示例',
          collapsed: false,
          items: [
            { text: '能力总览', link: '/sdk/overview' },
            { text: '示例用法', link: '/sdk/examples' },
          ],
        },
        {
          text: '核心用法',
          collapsed: false,
          items: [
            { text: '两个入口：query 与 Client', link: '/sdk/query-and-client' },
            { text: 'Options 配置', link: '/sdk/options' },
            { text: '消息模型', link: '/sdk/messages' },
            { text: '运行一个 PoA（poa feature）', link: '/sdk/running-a-poa' },
          ],
        },
        {
          text: '接口索引',
          link: '/sdk/api-index',
        },
        {
          text: '工具与扩展',
          collapsed: false,
          items: [
            { text: '内置工具目录', link: '/sdk/builtin-tools' },
            { text: '自定义工具 FunctionTools', link: '/sdk/tools' },
            { text: 'Hooks 生命周期钩子', link: '/sdk/hooks' },
          ],
        },
        {
          text: '运行时与治理',
          collapsed: false,
          items: [
            { text: '会话管理', link: '/sdk/sessions' },
            { text: '会话导出 transcript', link: '/sdk/transcript' },
            { text: '权限模型', link: '/sdk/permissions' },
            { text: '错误处理', link: '/sdk/errors' },
            { text: '中断与护栏', link: '/sdk/interrupt-and-guardrails' },
            { text: '边界与路线图', link: '/sdk/limits' },
          ],
        },
      ],
      '/sdk-py/': [
        {
          text: '入门与示例',
          collapsed: false,
          items: [
            { text: '能力总览', link: '/sdk-py/overview' },
            { text: '示例用法', link: '/sdk-py/examples' },
            { text: '接口速览', link: '/sdk-py/api-planning' },
          ],
        },
        {
          text: '核心用法',
          collapsed: false,
          items: [
            { text: '两个入口：query 与 Client', link: '/sdk-py/query-and-client' },
            { text: 'Options 配置', link: '/sdk-py/options' },
            { text: '消息模型', link: '/sdk-py/messages' },
          ],
        },
        {
          text: '接口索引',
          link: '/sdk-py/api-index',
        },
        {
          text: '工具与扩展',
          collapsed: false,
          items: [
            { text: '内置工具目录', link: '/sdk-py/builtin-tools' },
            { text: '自定义工具', link: '/sdk-py/tools' },
            { text: 'Hooks 生命周期钩子', link: '/sdk-py/hooks' },
          ],
        },
        {
          text: '运行时与治理',
          collapsed: false,
          items: [
            { text: '会话管理', link: '/sdk-py/sessions' },
            { text: '权限模型', link: '/sdk-py/permissions' },
            { text: '错误处理', link: '/sdk-py/errors' },
            { text: '边界与路线图', link: '/sdk-py/limits' },
          ],
        },
      ],
    },

    search: { provider: 'local' },

    socialLinks: [
      // 实施时确认仓库地址后填入：
      // { icon: 'github', link: 'https://github.com/<org>/brainary-rs' },
    ],

    docFooter: {
      prev: '上一页',
      next: '下一页',
    },

    outline: { label: '本页目录', level: [2, 3] },
    lastUpdatedText: '最后更新',
    returnToTopLabel: '回到顶部',
    sidebarMenuLabel: '菜单',
    darkModeSwitchLabel: '主题',
  },

  markdown: {
    toc: { level: [1, 2, 3] },
  },

  // 编译期 __DOCS_ROOT__ 注入（build+dev）+ dev 监听排除 + 单源代理 HMR 直连（见文件顶部说明）。
  ...viteOverride,
}))
