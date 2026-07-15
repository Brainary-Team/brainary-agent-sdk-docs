#!/bin/sh
# ─────────────────────────────────────────────────────────────
# Brainary CLI 安装脚本（macOS / Apple Silicon）
#
#   curl -fsSL https://docs.lzbrainary.com/install.sh | sh
#
# 流程：检测 macOS → 检测 arm64 → 下载 brainary 二进制 → 写入 PATH
#       → 创建 ~/.brainary/config.toml 配置模板（已存在则保留不覆盖）。
#
# 二进制托管在 GitHub Release，随最新 release 自动更新。
# 设计约束：本脚本经 `curl | sh` 执行时 stdin 是管道而非键盘，
#           因此不做任何键盘交互，只写占位配置、由用户事后填写。
# ─────────────────────────────────────────────────────────────
set -eu

# ── 常量 ─────────────────────────────────────────────────────
REPO="Brainary-Team/brainary-agent-sdk-docs"
BIN_URL="https://github.com/${REPO}/releases/latest/download/brainary"
BRAINARY_HOME="${HOME}/.brainary"
INSTALL_DIR="${BRAINARY_HOME}/bin"
BIN_PATH="${INSTALL_DIR}/brainary"
CONFIG_PATH="${BRAINARY_HOME}/config.toml"

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

printf '\n%s  Brainary CLI 安装程序%s\n' "$C_BOLD" "$C_RESET"
printf '%s  macOS · Apple Silicon%s\n\n' "$C_DIM" "$C_RESET"

# ── 1. 操作系统检测：仅支持 macOS ────────────────────────────
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
  die "Brainary 目前仅支持 macOS，检测到「${OS}」。安装已终止。"
fi

# ── 2. 架构检测：仅支持 Apple Silicon (arm64) ────────────────
ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
  printf '\n%s✗ Brainary 仅支持 Apple Silicon（arm64）芯片，检测到「%s」。%s\n' "$C_RED" "$ARCH" "$C_RESET" >&2
  printf '  暂无 Intel（x86_64）版本，安装已终止。\n\n' >&2
  exit 1
fi
ok "环境检测通过：macOS · Apple Silicon (${ARCH})"

# 已装过则本次是「更新」，否则是「安装」——用于后续文案。
if [ -x "$BIN_PATH" ]; then ACTION="更新"; else ACTION="安装"; fi

# ── 3. 下载二进制 ────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || die "未找到 curl，请先安装后重试。"

info "正在${ACTION} brainary 二进制…"
step "  来源：GitHub Release (latest)"
mkdir -p "$INSTALL_DIR"
TMP_BIN="$(mktemp "${TMPDIR:-/tmp}/brainary.XXXXXX")"
# 出错/中断时清理临时文件
trap 'rm -f "$TMP_BIN"' EXIT INT TERM

if ! curl -fSL --progress-bar "$BIN_URL" -o "$TMP_BIN"; then
  die "下载失败：${BIN_URL}
    请检查网络连接后重试。"
fi

# 校验下载确为 macOS 二进制（防止把 HTML 报错页/半截文件当成程序装进去）。
if ! file -b "$TMP_BIN" 2>/dev/null | grep -q 'Mach-O'; then
  die "下载内容不是有效的 macOS 二进制（可能是网络错误页或文件损坏）。
    请稍后重试；若持续失败，请反馈给我们。"
fi

chmod 755 "$TMP_BIN"
# 兜底：清除可能的隔离属性（curl 下载通常不会打，但防御性处理，忽略失败）
xattr -d com.apple.quarantine "$TMP_BIN" 2>/dev/null || true
mv -f "$TMP_BIN" "$BIN_PATH"
trap - EXIT INT TERM
ok "二进制已就位：${BIN_PATH}"

# ── 4. 配置文件：不存在才写模板，存在则保留（避免抹掉用户已填的 key）──
CONFIG_IS_NEW=0
if [ -f "$CONFIG_PATH" ]; then
  warn "已有配置，保留不覆盖：${CONFIG_PATH}"
else
  cat > "$CONFIG_PATH" <<'TOML'
[model]
name = "gpt-4o-mini"
api_url = "https://api.openai.com/v1"
api_key = "在此填入你的 API Key（如 sk-...）"
TOML
  CONFIG_IS_NEW=1
  ok "已创建配置模板：${CONFIG_PATH}"
fi

# ── 5. 接入 PATH ─────────────────────────────────────────────
# 安装目录免 sudo，与配置同在 ~/.brainary 下（模仿 deno/bun 的做法）。
PATH_TOUCHED=0
add_to_path() {
  rc_file="$1"
  line="export PATH=\"\$HOME/.brainary/bin:\$PATH\""
  # 已在 rc 里则跳过，避免重复追加
  if [ -f "$rc_file" ] && grep -qF '.brainary/bin' "$rc_file"; then
    return 0
  fi
  {
    printf '\n# Brainary CLI\n'
    printf '%s\n' "$line"
  } >> "$rc_file"
  PATH_TOUCHED=1
  ok "已写入 PATH：${rc_file}"
}

case "${SHELL:-}" in
  */zsh)  RC_FILE="${HOME}/.zshrc" ;;
  */bash) RC_FILE="${HOME}/.bash_profile" ;;
  *)      RC_FILE="${HOME}/.profile" ;;
esac
add_to_path "$RC_FILE"

# ── 6. 收尾提示 ──────────────────────────────────────────────
printf '\n%s✔ %s完成！%s\n\n' "$C_GREEN$C_BOLD" "$ACTION" "$C_RESET"
printf '  %s二进制%s  %s\n' "$C_DIM" "$C_RESET" "$BIN_PATH"
printf '  %s配置  %s  %s\n\n' "$C_DIM" "$C_RESET" "$CONFIG_PATH"

printf '%s下一步%s\n' "$C_BOLD" "$C_RESET"
n=1
if [ "$CONFIG_IS_NEW" -eq 1 ]; then
  printf '  %s.%s 编辑配置，把 %sapi_key%s 换成你的真实 Key：\n' "$n" "" "$C_YELLOW" "$C_RESET"
  printf '       %s${EDITOR:-vi} %s%s\n' "$C_CYAN" "$CONFIG_PATH" "$C_RESET"
  n=$((n+1))
fi
if [ "$PATH_TOUCHED" -eq 1 ]; then
  printf '  %s.%s 让当前终端立即生效（或重开一个终端）：\n' "$n" ""
  printf '       %sexport PATH="$HOME/.brainary/bin:$PATH"%s\n' "$C_CYAN" "$C_RESET"
  n=$((n+1))
fi
printf '  %s.%s 运行：\n' "$n" ""
printf '       %sbrainary --help%s   %s# 或 brainary demo%s\n\n' "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
