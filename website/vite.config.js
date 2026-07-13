import { defineConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite'

// 官网构建配置。
// base: './' → 产物用相对路径引用资源，扔到静态服务器根（/）即可用；
//   与文档站 base:'/docs/' 相互独立（见方案 4.2 / 4.5）。
// server/preview 固定 5174 → 避开文档站占死的 5173（--strictPort，见方案 4.5）。
//
// dev 期单源代理（仅 dev server 生效，不影响 build 产物）：
//   start-docs.sh 同时启动官网与文档两个 dev server 时，会设 DOCS_PROXY_TARGET
//   指向文档 dev（如 http://127.0.0.1:5173）。此处据它把 /docs 反代到文档站，
//   让 dev 和 build 一样单源同址——官网在 /、文档在 /docs/，官网里写死的
//   <a href="/docs/"> 在 dev 也能正常跳（否则会命中官网自身 5174 → 404/空白）。
//   ws:true 转发 websocket；未设该变量时不加 proxy，行为完全不变。
const docsProxyTarget = process.env.DOCS_PROXY_TARGET

export default defineConfig({
  base: './',
  plugins: [tailwindcss()],
  server: {
    port: 5174,
    strictPort: true,
    ...(docsProxyTarget && {
      proxy: {
        '/docs': { target: docsProxyTarget, changeOrigin: true, ws: true },
      },
    }),
  },
  preview: { port: 5174, strictPort: true },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
