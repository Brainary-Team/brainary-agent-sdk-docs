// 自定义主题：在默认主题基础上，往顶栏注入版本切换下拉框。
// 用 nav-bar-content-before slot → 下拉框落在 Python/Rust 链接左侧（贴近 Python 官方文档位置）。
import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import VersionSwitcher from './VersionSwitcher.vue'

export default {
  extends: DefaultTheme,
  Layout: () =>
    h(DefaultTheme.Layout, null, {
      'nav-bar-content-before': () => h(VersionSwitcher),
    }),
}
