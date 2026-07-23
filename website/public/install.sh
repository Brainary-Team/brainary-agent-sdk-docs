#!/bin/sh
# ─────────────────────────────────────────────────────────────
# Brainary CLI 安装脚本（macOS / Apple Silicon）—— 终端输出为英文
#
#   curl -fsSL https://docs.lzbrainary.com/install.sh | sh
#
# 流程：检测 macOS → 检测 arm64 → 下载 brainary 二进制 → 写入 PATH
#       → 创建 ~/.brainary/config.toml 配置模板（已存在则保留不覆盖）。
#
# 二进制托管在 GitHub Release，随最新 release 自动更新。
# 设计约束：
#   · 本脚本经 `curl | sh` 执行时 stdin 是管道而非键盘，不做键盘交互，
#     只写占位配置、由用户事后填写。
#   · curl|sh 是子进程，无法改当前终端的 PATH；故把 ~/.brainary/bin 写进
#     shell 配置文件，用户「重开终端」后即可直接敲 brainary（不使用 sudo）。
#   · 可重复执行（幂等）：二进制覆盖更新、配置保留、PATH 去重。
# ─────────────────────────────────────────────────────────────
set -eu

# ── 常量 ─────────────────────────────────────────────────────
REPO="Brainary-Team/brainary-agent-sdk-docs"
BIN_URL="https://github.com/${REPO}/releases/latest/download/brainary"
BRAINARY_HOME="${HOME}/.brainary"
INSTALL_DIR="${BRAINARY_HOME}/bin"
BIN_PATH="${INSTALL_DIR}/brainary"
CONFIG_PATH="${BRAINARY_HOME}/config.toml"
PATH_LINE='export PATH="$HOME/.brainary/bin:$PATH"'

# ── 输出着色（仅在连到终端时上色，管道/重定向时保持纯文本）──
if [ -t 1 ]; then
  C_RESET="$(printf '\033[0m')"; C_RED="$(printf '\033[31m')"
  C_GREEN="$(printf '\033[32m')"; C_YELLOW="$(printf '\033[33m')"
  C_CYAN="$(printf '\033[36m')"; C_DIM="$(printf '\033[2m')"; C_BOLD="$(printf '\033[1m')"
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_DIM=""; C_BOLD=""
fi

info()  { printf '%s▸%s %s\n' "$C_CYAN" "$C_RESET" "$1"; }
ok()    { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
step()  { printf '%s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
die()   { printf '\n%s✗ %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

printf '\n%s  Brainary CLI Installer%s\n' "$C_BOLD" "$C_RESET"
printf '%s  macOS · Apple Silicon%s\n\n' "$C_DIM" "$C_RESET"

# ── 1. 操作系统检测：仅支持 macOS ────────────────────────────
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
  die "Brainary currently supports macOS only (detected \"${OS}\"). Aborting."
fi

# ── 2. 架构检测：仅支持 Apple Silicon (arm64) ────────────────
ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
  printf '\n%s✗ Brainary requires Apple Silicon (arm64), but detected "%s".%s\n' "$C_RED" "$ARCH" "$C_RESET" >&2
  printf '  No Intel (x86_64) build is available yet. Aborting.\n\n' >&2
  exit 1
fi
ok "Environment OK: macOS · Apple Silicon (${ARCH})"

# 已装过则本次是「更新」，否则是「安装」——用于后续文案。
if [ -x "$BIN_PATH" ]; then VERB="Updating"; DONE="Update complete"; else VERB="Installing"; DONE="Installation complete"; fi

# ── 3. 下载二进制 ────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || die "curl not found. Please install it and retry."

info "${VERB} the brainary binary…"
step "  source: GitHub Release (latest)"
mkdir -p "$INSTALL_DIR"
TMP_BIN="$(mktemp "${TMPDIR:-/tmp}/brainary.XXXXXX")"
# 出错/中断时清理临时文件
trap 'rm -f "$TMP_BIN"' EXIT INT TERM

if ! curl -fSL --progress-bar "$BIN_URL" -o "$TMP_BIN"; then
  die "Download failed: ${BIN_URL}
    Please check your network connection and try again."
fi

# 校验下载确为 macOS 二进制（防止把 HTML 报错页/半截文件当成程序装进去）。
if ! file -b "$TMP_BIN" 2>/dev/null | grep -q 'Mach-O'; then
  die "The downloaded file is not a valid macOS binary (network error page or corrupted download).
    Please try again; if it keeps failing, let us know."
fi

chmod 755 "$TMP_BIN"
# 兜底：清除可能的隔离属性（curl 下载通常不会打，但防御性处理，忽略失败）
xattr -d com.apple.quarantine "$TMP_BIN" 2>/dev/null || true
# 原子替换：mv 到同一文件系统的目标路径，避免运行中被替换出现半截文件。
mv -f "$TMP_BIN" "$BIN_PATH"
trap - EXIT INT TERM
ok "Binary installed: ${BIN_PATH}"

# ── 4. 配置文件：不存在才写模板，存在则保留（避免抹掉用户已填的 key）──
CONFIG_IS_NEW=0
if [ -f "$CONFIG_PATH" ]; then
  warn "Existing config kept (not overwritten): ${CONFIG_PATH}"
else
  cat > "$CONFIG_PATH" <<'TOML'
[model]
name = "gpt-4o-mini"
api_url = "https://api.openai.com/v1"
# Replace the placeholder below with your own API key (e.g. sk-...).
api_key = "YOUR_API_KEY_HERE"
TOML
  CONFIG_IS_NEW=1
  ok "Config template created: ${CONFIG_PATH}"
fi

# ── 5. 接入 PATH：写 shell 配置，重开终端即生效（不用 sudo）──────
# 按登录 shell 选对应 rc；未知 shell 落到通用 ~/.profile。
case "${SHELL:-}" in
  */zsh)  RC_FILE="${HOME}/.zshrc" ;;
  */bash) RC_FILE="${HOME}/.bash_profile" ;;
  *)      RC_FILE="${HOME}/.profile" ;;
esac

if [ -f "$RC_FILE" ] && grep -qF '.brainary/bin' "$RC_FILE"; then
  step "  PATH already set in ${RC_FILE}, skipping"
elif { printf '\n# Brainary CLI\n%s\n' "$PATH_LINE" >> "$RC_FILE"; } 2>/dev/null; then
  ok "Added to PATH: ${RC_FILE}"
else
  warn "Could not update ${RC_FILE} automatically. Add this line to your shell config manually:"
  printf '       %s%s%s\n' "$C_CYAN" "$PATH_LINE" "$C_RESET"
fi

# 判断当前终端是否已经能找到 brainary（二次运行 / 已重开过终端 / 手动 export 过）。
ON_PATH=0
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ON_PATH=1 ;;
esac

# ── 探测已安装版本（仅用于展示）──────────────────────────────
# 优先让二进制自报版本（brainary --version）；若该 flag 不被支持 / 二进制无法执行，
# 回退到 GitHub Release 的 tag_name（与官网版本徽标同源）。都取不到则留空、不展示——
# 探测失败绝不中断安装（if 条件里的失败不触发 set -e；curl 回退加 || true 兜底）。
INSTALLED_VERSION=""
if _v="$("$BIN_PATH" --version 2>/dev/null)" && [ -n "$_v" ]; then
  INSTALLED_VERSION="$_v"
else
  _tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
    | sed 's/.*"\([^"]*\)"$/\1/' || true)"
  [ -n "$_tag" ] && INSTALLED_VERSION="$_tag"
fi

# ── 6. 收尾提示 ──────────────────────────────────────────────
printf '\n%s✔ %s!%s\n\n' "$C_GREEN$C_BOLD" "$DONE" "$C_RESET"
[ -n "$INSTALLED_VERSION" ] && printf '  %sversion%s %s\n' "$C_DIM" "$C_RESET" "$INSTALLED_VERSION"
printf '  %sbinary%s  %s\n' "$C_DIM" "$C_RESET" "$BIN_PATH"
printf '  %sconfig%s  %s\n\n' "$C_DIM" "$C_RESET" "$CONFIG_PATH"

printf '%sNext steps%s\n' "$C_BOLD" "$C_RESET"
n=1
if [ "$CONFIG_IS_NEW" -eq 1 ]; then
  printf '  %s. Edit the config and replace %sapi_key%s with your real key:\n' "$n" "$C_YELLOW" "$C_RESET"
  printf '       %s${EDITOR:-vi} %s%s\n' "$C_CYAN" "$CONFIG_PATH" "$C_RESET"
  n=$((n+1))
fi
if [ "$ON_PATH" -eq 1 ]; then
  printf '  %s. Run it now (brainary is already on your PATH):\n' "$n"
  printf '       %sbrainary --help%s   %s# or: brainary demo%s\n\n' "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
else
  printf '  %s. %sOpen a new terminal%s (or run %ssource %s%s) to apply PATH\n' "$n" "$C_BOLD" "$C_RESET" "$C_CYAN" "$RC_FILE" "$C_RESET"
  n=$((n+1))
  printf '  %s. Then run:\n' "$n"
  printf '       %sbrainary --help%s   %s# or: brainary demo%s\n\n' "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
fi
