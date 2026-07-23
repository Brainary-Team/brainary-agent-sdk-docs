#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Brainary 文档发版冻结脚本（Python 式版本快照）
#
#   把 user_docs/ 当前源码构建成一个「冻结版本」，产物存入
#   user_docs/.versions/<VER>/ 并提交进 git —— 该版本此后永不重建。
#   同时更新可变清单 user_docs/public/versions.json（新增该版本、置为 latest）。
#   清单放在 public/ 是刻意为之：VitePress 在 dev 与 build 都把 public/ 挂到 base 根，
#   故 dev（vitepress dev）也能在 /docs/versions.json 取到清单 → 版本下拉框在 dev 可见。
#
# 版本号（VER）= URL 段，采用 semver，与 CLI 二进制的 GitHub release tag 对齐（如 v0.0.1）。
# 版本号由 --version 显式给定，完全自治、不再从 brainary-rs 提交派生（已去除 hash 溯源）。
# 发布日期默认取运行当天（--date 可覆盖），仅作下拉标签展示用。
#
#   用法：
#     ./snapshot.sh --version v0.0.1              # 冻结为版本 v0.0.1（日期取当天）
#     ./snapshot.sh --version v0.0.1 --date <YYYY-MM-DD>   # 显式指定发布日期
#     任意上式可加 --replace                       # 替换而非追加：只保留这一版（见文末说明）
#
#   冻结不可覆盖：若 .versions/<VER> 已存在，脚本拒绝执行（除非 --replace）。
#   要修正已发布版本，请手动删除该目录后重跑（或用 --replace）。
#
#   --replace  替换模式：不追加、只保留这一版。冻结前清掉 .versions/ 下所有既有版本
#              目录（含同名 VER，故可覆盖重冻），并把 versions.json 重置为「仅含新版本」
#              一条。预 tag 阶段防版本堆积；semver 阶段用于替换重冻同一版本。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_DIR="$ROOT/user_docs/.versions"   # 各版本冻结产物：.versions/<ver>/
MANIFEST="$ROOT/user_docs/public/versions.json"   # 可变清单（VitePress public 资源）

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ── 载入部署基路径 SITE_BASE（决定冻结产物 base 前缀）─────────
# 环境变量优先，其次 deploy.env，默认 '/'（根/dev）。规范化为首尾带 '/'。
if [ -z "${SITE_BASE:-}" ] && [ -f "$ROOT/deploy.env" ]; then
  SITE_BASE="$(sed -n 's/^[[:space:]]*SITE_BASE=//p' "$ROOT/deploy.env" | tail -n1)"
fi
SITE_BASE="${SITE_BASE:-/}"
case "$SITE_BASE" in /*) ;; *) SITE_BASE="/$SITE_BASE" ;; esac
case "$SITE_BASE" in */) ;; *) SITE_BASE="$SITE_BASE/" ;; esac
export SITE_BASE

# ── 解析参数 ───────────────────────────────────────────────
VER=""; CDATE=""; REPLACE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VER="${2:-}"; shift 2 ;;
    --date)    CDATE="${2:-}"; shift 2 ;;
    --replace) REPLACE=1; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         fail "未知参数：$1（用法见 ./snapshot.sh --help）" ;;
  esac
done

command -v pnpm >/dev/null 2>&1 || fail "未找到 pnpm。安装：curl -fsSL https://get.pnpm.io/install.sh | sh -"

# ── 确定版本号与发布日期 ───────────────────────────────────
[ -n "$VER" ] || fail "缺少版本号。用法：./snapshot.sh --version v0.0.1 [--date YYYY-MM-DD] [--replace]"
# 发布日期默认取运行当天（仅作下拉标签展示；--date 可覆盖）。
CDATE="${CDATE:-$(date +%F)}"
step "版本：${VER}（发布日期 ${CDATE}）"

# 版本号即 URL 段，须为 URL 安全字符（兼容 semver，如 v0.0.1）。
[[ "$VER" =~ ^[0-9A-Za-z._-]+$ ]] || fail "版本号含非法字符：${VER}（仅允许 [0-9A-Za-z._-]）"

DEST="$VERSIONS_DIR/$VER"
if [ "$REPLACE" -eq 1 ]; then
  # 替换模式：清掉所有既有冻结版本目录（含同名 VER），只留即将冻结的这一版。
  if [ -d "$VERSIONS_DIR" ] && [ -n "$(ls -A "$VERSIONS_DIR" 2>/dev/null || true)" ]; then
    step "替换模式：移除既有冻结版本（$(ls -A "$VERSIONS_DIR" | tr '\n' ' ')）"
    find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
else
  [ -e "$DEST" ] && fail "版本 $VER 已冻结（$DEST 已存在），拒绝覆盖。用 --replace 可替换重冻。"
fi

# ── 1. 以 <SITE_BASE>docs/<VER>/ 为 base 构建当前源码 ───────
step "构建文档 user_docs（DOCS_VERSION=$VER → base '${SITE_BASE}docs/$VER/'）"
pnpm --dir "$ROOT/user_docs" install
SITE_BASE="$SITE_BASE" DOCS_VERSION="$VER" pnpm --dir "$ROOT/user_docs" run docs:build

# ── 2. 归档冻结 ────────────────────────────────────────────
step "冻结产物 → user_docs/.versions/$VER/"
mkdir -p "$DEST"
cp -R "$ROOT/user_docs/.vitepress/dist/." "$DEST/"

# ── 3. 更新可变清单 versions.json（public/ 资源）──────────
step "更新 versions.json（新增 $VER 并置为 latest）"
mkdir -p "$(dirname "$MANIFEST")"
MANIFEST="$MANIFEST" VER="$VER" CDATE="$CDATE" REPLACE="$REPLACE" node -e '
  const fs = require("fs");
  const { MANIFEST, VER, CDATE, REPLACE } = process.env;
  let data = { latest: "", versions: [] };
  // 替换模式从空清单起（丢弃旧版本条目），只保留即将加入的这一版；否则读现有清单追加。
  if (REPLACE !== "1" && fs.existsSync(MANIFEST)) data = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  data.versions = (data.versions || []).filter(v => v.version !== VER);
  const entry = { version: VER, stable: true };
  if (CDATE) entry.date = CDATE;
  data.versions.unshift(entry);
  data.latest = VER;
  // 标签由 version + 日期派生：`<ver> · <date>`（无日期则裸版本号）；latest 追加 (latest)。
  for (const v of data.versions) {
    const base = v.date ? (v.version + " · " + v.date) : v.version;
    v.label = base + (v.version === data.latest ? " (latest)" : "");
  }
  fs.writeFileSync(MANIFEST, JSON.stringify(data, null, 2) + "\n");
  console.log("  latest =", data.latest, "| versions:", data.versions.map(v => v.version).join(", "));
'

printf '\n\033[1;32m✔ 已冻结 %s\033[0m\n' "$VER"
echo "    请提交：git add user_docs/.versions user_docs/public/versions.json && git commit -m \"docs: 冻结文档版本 $VER\""
echo "    然后跑 ./build.sh 组装含全部版本的 dist/"
