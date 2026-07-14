// 站点级共享配置：品牌、导航项、文档入口、页脚。
// nav / footer partial 与页面均从此处取值，未来加多页时改这一处即可。
export const site = {
  brand: 'Brainary',
  brandZh: '领智智能',
  // 文档入口：部署后与官网同源，文档挂在 <base>docs/（方案 4.1）。
  // 用「相对」路径：官网是站点根的单页，相对 docs/ 在根部署(/docs/)与
  // GitHub Pages 子路径(/brainary-docs/docs/)下都能正确解析，无需知道 base。
  docsUrl: 'docs/',
  // 未来 Brainary Code 产品文档，尚未上线 → 占位（方案 5.3）。
  codeDocsUrl: '#',
  // 「安装 CLI」不再是下载按钮，而是一行可复制的安装命令（macOS / Linux）。
  // ⚠ 占位：install.sh 端点尚未上线，待子乔提供真实安装源后替换（方案 6 待办）。
  //   单一真源：main.js 会把此串写进页面所有 [data-install-cmd]，HTML 里的同串仅作无-JS 兜底。
  //   禁止编造第三方地址；此处用站点自有域名，脚本可后续放进 website/public/install.sh。
  cliInstallCmd: 'curl -fsSL https://docs.lzbrainary.com/install.sh | sh',
  // 导航/页脚「安装 CLI」指向首屏安装命令框（锚点）。
  installAnchor: '#install',
  year: 2026,
}

// 顶部导航项。external=true 走真实跳转（如 /docs/），并在新标签页打开、保留官网；soon=true 标注即将上线。
// key 对应 i18n 字典 nav.<key>，label 为中文兜底（无 JS 时显示）。
export const navLinks = [
  { key: 'home', label: '首页', href: '#top' },
  { key: 'capabilities', label: '能力', href: '#capabilities' },
  { key: 'sdk', label: 'SDK 文档', href: site.docsUrl, external: true },
  { key: 'code', label: 'Code SDK', href: site.codeDocsUrl, soon: true },
]
