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
# 版本号（VER）= URL 段。当前处于「预 tag 阶段」：SDK 尚无正式版本/tag，故版本号
# 直接取所关联的 brainary-rs 提交短 hash（默认 origin/master 最新），可溯源到源码提交。
# 正式 tag 建立后，用 --version 显式传 semver 即可无缝切换（清单支持任意版本字符串）。
#
#   用法：
#     ./snapshot.sh                       # 自动：取 brainary-rs origin/master 最新 → 短 hash 版本
#     ./snapshot.sh --ref <gitref>        # 自动：取指定 ref（分支/tag/commit）的短 hash 版本
#     ./snapshot.sh --version <str> \     # 显式：给定版本号（未来 semver / brainary-rs 不在场时）
#         [--commit <fullhash>] [--date <YYYY-MM-DD>]
#   环境变量：
#     BRAINARY_RS_DIR   brainary-rs 仓库路径（默认 ../brainary-rs）
#     RS_REF            自动派生所用 ref（默认 origin/master；--ref 覆盖之）
#   提示：自动派生前先在 brainary-rs 里 `git fetch`，确保 origin/master 是最新的。
#         brainary-rs 默认主干是 master 而非 main。
#
#   冻结不可覆盖：若 .versions/<VER> 已存在，脚本拒绝执行。
#   要修正已发布版本，请手动删除该目录后重跑（明确知道自己在做什么）。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_DIR="$ROOT/user_docs/.versions"   # 各版本冻结产物：.versions/<ver>/
MANIFEST="$ROOT/user_docs/public/versions.json"   # 可变清单（VitePress public 资源）
RS_DIR="${BRAINARY_RS_DIR:-$ROOT/../brainary-rs}"  # 关联的 brainary-rs 仓库
RS_REF="${RS_REF:-origin/master}"                  # 默认主干最新（注意：master 不是 main）

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
VER=""; COMMIT=""; CDATE=""; SUBJ=""; EXPLICIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ref)     RS_REF="${2:-}"; shift 2 ;;
    --version) VER="${2:-}"; EXPLICIT=1; shift 2 ;;
    --commit)  COMMIT="${2:-}"; shift 2 ;;
    --date)    CDATE="${2:-}"; shift 2 ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         fail "未知参数：$1（用法见 ./snapshot.sh --help）" ;;
  esac
done

command -v pnpm >/dev/null 2>&1 || fail "未找到 pnpm。安装：curl -fsSL https://get.pnpm.io/install.sh | sh -"

# ── 派生版本号与溯源元数据 ─────────────────────────────────
if [ "$EXPLICIT" -eq 1 ]; then
  [ -n "$VER" ] || fail "--version 后需跟版本号"
  step "显式版本：${VER}${COMMIT:+（commit ${COMMIT}）}"
else
  # 自动：从 brainary-rs 指定 ref 派生短 hash + 提交日期/主题
  [ -d "$RS_DIR/.git" ] || fail "未找到 brainary-rs 仓库：$RS_DIR
  可设 BRAINARY_RS_DIR 指向它，或改用 ./snapshot.sh --version <str> [--commit <hash>] [--date <YYYY-MM-DD>] 显式发版。"
  git -C "$RS_DIR" rev-parse --verify --quiet "$RS_REF^{commit}" >/dev/null \
    || fail "brainary-rs 里无法解析 ref '$RS_REF'（注意默认主干是 master，不是 main）。
  可用 --ref <分支/tag/commit> 或 RS_REF 环境变量指定。"
  VER="$(git -C "$RS_DIR" rev-parse --short "$RS_REF")"
  COMMIT="$(git -C "$RS_DIR" rev-parse "$RS_REF")"
  CDATE="$(git -C "$RS_DIR" show -s --format=%cs "$RS_REF")"
  SUBJ="$(git -C "$RS_DIR" show -s --format=%s "$RS_REF")"
  step "自动派生：brainary-rs ${RS_REF} → 版本 ${VER}（${CDATE}｜${SUBJ}）"
fi

# 版本号即 URL 段，须为 URL 安全字符（放宽自数字正则，兼容 hash 与 semver）。
[[ "$VER" =~ ^[0-9A-Za-z._-]+$ ]] || fail "版本号含非法字符：${VER}（仅允许 [0-9A-Za-z._-]）"

DEST="$VERSIONS_DIR/$VER"
[ -e "$DEST" ] && fail "版本 $VER 已冻结（$DEST 已存在），拒绝覆盖。"

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
MANIFEST="$MANIFEST" VER="$VER" COMMIT="$COMMIT" CDATE="$CDATE" SUBJ="$SUBJ" RS_REF="$RS_REF" node -e '
  const fs = require("fs");
  const { MANIFEST, VER, COMMIT, CDATE, SUBJ, RS_REF } = process.env;
  let data = { latest: "", versions: [] };
  if (fs.existsSync(MANIFEST)) data = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  data.versions = (data.versions || []).filter(v => v.version !== VER);
  const entry = { version: VER, stable: true };
  if (COMMIT) entry.commit = COMMIT;
  if (CDATE)  entry.date = CDATE;
  if (RS_REF) entry.ref = RS_REF;
  if (SUBJ)   entry.subject = SUBJ;
  data.versions.unshift(entry);
  data.latest = VER;
  // 标签由 version + 日期派生：有日期则 `rs@<ver> · <date>`，否则裸版本号；latest 追加 (latest)。
  for (const v of data.versions) {
    const base = v.date ? ("rs@" + v.version + " · " + v.date) : v.version;
    v.label = base + (v.version === data.latest ? " (latest)" : "");
  }
  fs.writeFileSync(MANIFEST, JSON.stringify(data, null, 2) + "\n");
  console.log("  latest =", data.latest, "| versions:", data.versions.map(v => v.version).join(", "));
'

printf '\n\033[1;32m✔ 已冻结 %s\033[0m\n' "$VER"
echo "    请提交：git add user_docs/.versions user_docs/public/versions.json && git commit -m \"docs: 冻结文档版本 $VER\""
echo "    然后跑 ./build.sh 组装含全部版本的 dist/"
