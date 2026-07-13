#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Brainary 站点一键构建 + 组装（方案 4.2 第 4 步 / 5.5）
#
#   官网（website/，Vite）        → 顶层 dist/           作为 /
#   文档（user_docs/，已冻结版本） → 顶层 dist/docs/<ver>/ 作为 /docs/<ver>/
#
# 文档采用 Python 式版本冻结：build.sh 不再实时构建文档，而是直接组装
# user_docs/.versions/ 下已冻结的各版本产物（由 ./snapshot.sh <ver> 生成）。
# 另生成 dist/docs/index.html：运行时读 versions.json 重定向到 latest。
#
# 产物顶层 dist/ 自包含、无 CDN 外链，可直接放到静态服务器根。
# 用法：./build.sh          （组装官网 + 全部冻结文档版本）
#       ./build.sh --serve  （组装后本地起静态服务器预览 :8080）
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
VERSIONS_DIR="$ROOT/user_docs/.versions"          # 各版本冻结产物：.versions/<ver>/
MANIFEST="$ROOT/user_docs/public/versions.json"   # 可变清单（VitePress public 资源）

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }

# ── 部署基路径 SITE_BASE（须与冻结产物烤进的 base 一致；见 deploy.env）──
# 环境变量优先，其次 deploy.env，默认 '/'。规范化为首尾带 '/'。
if [ -z "${SITE_BASE:-}" ] && [ -f "$ROOT/deploy.env" ]; then
  SITE_BASE="$(sed -n 's/^[[:space:]]*SITE_BASE=//p' "$ROOT/deploy.env" | tail -n1)"
fi
SITE_BASE="${SITE_BASE:-/}"
case "$SITE_BASE" in /*) ;; *) SITE_BASE="/$SITE_BASE" ;; esac
case "$SITE_BASE" in */) ;; *) SITE_BASE="$SITE_BASE/" ;; esac

command -v pnpm >/dev/null 2>&1 || {
  echo "✗ 未找到 pnpm。请先安装：curl -fsSL https://get.pnpm.io/install.sh | sh -" >&2
  exit 1
}

# ── 前置：至少要有一个已冻结版本 ───────────────────────────
[ -f "$MANIFEST" ] || {
  echo "✗ 未找到 $MANIFEST。请先冻结首版：./snapshot.sh 0.1" >&2
  exit 1
}
[ "$(ls -A "$VERSIONS_DIR" 2>/dev/null | grep -v '^versions.json$' || true)" ] || {
  echo "✗ $VERSIONS_DIR 下没有任何冻结版本目录。请先冻结：./snapshot.sh 0.1" >&2
  exit 1
}
LATEST="$(MANIFEST="$MANIFEST" node -e 'console.log(JSON.parse(require("fs").readFileSync(process.env.MANIFEST,"utf8")).latest)')"
[ -n "$LATEST" ] || { echo "✗ versions.json 里 latest 为空" >&2; exit 1; }
[ -d "$VERSIONS_DIR/$LATEST" ] || {
  echo "✗ latest=$LATEST 对应的冻结目录 $VERSIONS_DIR/$LATEST 不存在，请重跑 ./snapshot.sh $LATEST" >&2
  exit 1
}

# ── 1. 官网（Vite）─────────────────────────────────────────
step "构建官网 website → website/dist/"
pnpm --dir "$ROOT/website" install
pnpm --dir "$ROOT/website" run build

# ── 2. 组装顶层 dist/ ──────────────────────────────────────
step "组装 dist/（/ = 官网，/docs/<ver>/ = 冻结文档，latest=${LATEST}）"
rm -rf "$DIST"
mkdir -p "$DIST/docs"
cp -R "$ROOT/website/dist/." "$DIST/"
# .versions/ 里含各冻结版本目录，整体铺进 /docs/<ver>/
cp -R "$VERSIONS_DIR/." "$DIST/docs/"
# 可变清单铺到共享位置 /docs/versions.json（切换器运行时按绝对路径取它）
cp "$MANIFEST" "$DIST/docs/versions.json"

# 根落地页：运行时读 versions.json 跳到 latest；fetch 失败则用构建期注入的 latest 兜底。
# 所有绝对路径带 SITE_BASE 前缀（根部署为 /，GitHub Pages 子路径为 /brainary-docs/）。
cat > "$DIST/docs/index.html" <<HTML
<!doctype html><meta charset=utf-8><title>Brainary 文档</title>
<script>
fetch('${SITE_BASE}docs/versions.json').then(function(r){return r.json()})
  .then(function(d){location.replace('${SITE_BASE}docs/'+d.latest+'/sdk-py/overview.html')})
  .catch(function(){location.replace('${SITE_BASE}docs/${LATEST}/sdk-py/overview.html')});
</script>
<noscript><a href="${SITE_BASE}docs/${LATEST}/sdk-py/overview.html">进入文档</a></noscript>
HTML

# Pages 细节：禁用 Jekyll（避免处理 assets）；有 CNAME 则带上（自定义域名用）。
touch "$DIST/.nojekyll"
[ -f "$ROOT/CNAME" ] && cp "$ROOT/CNAME" "$DIST/CNAME" && echo "  带上自定义域名 CNAME：$(cat "$ROOT/CNAME")"

# ── 3. 无 CDN 外链自检（Tailwind 许可证注释里的 tailwindcss.com 属注释，忽略）──
step "自检：构建产物是否残留 CDN 外链"
if grep -rlE "cdn\.tailwindcss|fonts\.googleapis|fonts\.gstatic|unpkg\.com|jsdelivr\.net|cdnjs\.cloudflare" "$DIST" 2>/dev/null; then
  echo "✗ 检测到 CDN 外链，请检查上面文件！" >&2
  exit 1
fi
echo "✓ 未发现 CDN 外链"

printf '\n\033[1;32m✔ 完成\033[0m  产物在 %s（部署基路径 SITE_BASE=%s）\n' "$DIST" "$SITE_BASE"
echo "    ${SITE_BASE}              → 官网"
echo "    ${SITE_BASE}docs/         → 跳转到 latest（${LATEST}）"
echo "    ${SITE_BASE}docs/<ver>/   → 各冻结文档版本"

if [ "${1:-}" = "--serve" ]; then
  # 把 dist 挂在 SITE_BASE 子路径下再起服务，链接前缀才对（否则子路径下全 404）。
  SEG="${SITE_BASE#/}"; SEG="${SEG%/}"
  if [ -n "$SEG" ]; then
    STAGE="$(mktemp -d)"; mkdir -p "$STAGE/$SEG"; cp -R "$DIST/." "$STAGE/$SEG/"
    step "本地预览 http://127.0.0.1:8080${SITE_BASE}（Ctrl+C 结束）"
    cd "$STAGE" && python3 -m http.server 8080
  else
    step "本地预览 http://127.0.0.1:8080/（Ctrl+C 结束）"
    cd "$DIST" && python3 -m http.server 8080
  fi
fi
