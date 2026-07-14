#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Brainary 文档一键发布：冻结当前版本 → 提交 → 推送（触发 CI 部署）。
#
#   把 snapshot.sh（冻结）+ git add/commit/push 串成一条命令。推送到 main 后，
#   .github/workflows/deploy.yml 会自动 build 并部署到 GitHub Pages。
#
#   用法（参数原样透传给 snapshot.sh）：
#     ./release.sh                 # 冻结 brainary-rs origin/master 最新 → 短 hash 版本
#     ./release.sh --ref <gitref>  # 冻结指定 ref
#     ./release.sh --version 1.0   # 正式 semver 版本
#     ./release.sh --replace ...   # 替换而非追加：只保留这一版（预 tag 阶段防版本堆积）
#
#   提示：CI 部署仅从 main 分支触发。当前若在其它分支，本脚本照常提交推送该分支，
#         但需合并到 main（或在 GitHub Actions 手动 dispatch）才会真正部署。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$ROOT/user_docs/public/versions.json"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "未找到 git"

# 工作区须干净（除将要生成的冻结产物外），避免把无关改动一并提交。
if [ -n "$(git -C "$ROOT" status --porcelain -- user_docs/.versions user_docs/public/versions.json)" ]; then
  fail "user_docs/.versions 或 versions.json 有未提交改动，请先处理后再发版。"
fi

# ── 1. 冻结（透传全部参数给 snapshot.sh）─────────────────────
"$ROOT/snapshot.sh" "$@"

# ── 2. 读取刚冻结的版本号（snapshot.sh 已把它置为 latest）────
VER="$(MANIFEST="$MANIFEST" node -e 'console.log(JSON.parse(require("fs").readFileSync(process.env.MANIFEST,"utf8")).latest)')"
[ -n "$VER" ] || fail "无法从 $MANIFEST 读出 latest 版本号"
[ -d "$ROOT/user_docs/.versions/$VER" ] || fail "冻结目录 user_docs/.versions/$VER 不存在，发布中止"

# ── 3. 提交 ────────────────────────────────────────────────
# 替换模式会删除旧版本目录；用 -A 让 git 一并暂存这些删除（普通模式无副作用）。
case " $* " in *" --replace "*) MSG="docs: 替换冻结文档版本 ${VER}（只保留此版）" ;; *) MSG="docs: 冻结文档版本 ${VER}" ;; esac
step "提交冻结产物与清单（版本 $VER）"
git -C "$ROOT" add -A user_docs/.versions user_docs/public/versions.json
git -C "$ROOT" commit -m "$MSG"

# ── 4. 推送当前分支 ────────────────────────────────────────
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
step "推送分支 $BRANCH → origin"
git -C "$ROOT" push origin "$BRANCH"

printf '\n\033[1;32m✔ 已发布 %s（分支 %s）\033[0m\n' "$VER" "$BRANCH"
if [ "$BRANCH" = "main" ]; then
  echo "    已推送到 main → GitHub Actions 将自动构建并部署到 Pages。"
else
  echo "    注意：CI 部署仅从 main 触发。请把 $BRANCH 合并到 main（或在 Actions 手动 dispatch）以部署。"
fi
