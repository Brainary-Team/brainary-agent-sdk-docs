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
  C_CYAN="$(printf '\033[36m')"; C_BOLD="$(printf '\033[1m')"
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""
fi

info()  { printf '%s▸%s %s\n' "$C_CYAN" "$C_RESET" "$1"; }
ok()    { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
die()   { printf '%s✗ %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

printf '\n%sBrainary CLI 安装程序%s\n\n' "$C_BOLD" "$C_RESET"

# ── 1. 操作系统检测：仅支持 macOS ────────────────────────────
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
  die "Brainary 目前仅支持 macOS，检测到「${OS}」。安装已终止。"
fi

# ── 2. 架构检测：仅支持 Apple Silicon (arm64) ────────────────
ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
  printf '%s✗ Brainary 仅支持 Apple Silicon（arm64）芯片，检测到「%s」。%s\n' "$C_RED" "$ARCH" "$C_RESET" >&2
  printf '  暂无 Intel（x86_64）版本，安装已终止。\n' >&2
  exit 1
fi
ok "环境检测通过：macOS · Apple Silicon (${ARCH})"

# ── 3. 下载二进制 ────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || die "未找到 curl，请先安装后重试。"

info "正在下载 brainary 二进制…"
mkdir -p "$INSTALL_DIR"
TMP_BIN="$(mktemp "${TMPDIR:-/tmp}/brainary.XXXXXX")"
# 出错/中断时清理临时文件
trap 'rm -f "$TMP_BIN"' EXIT INT TERM

if ! curl -fSL --progress-bar "$BIN_URL" -o "$TMP_BIN"; then
  die "下载失败：${BIN_URL}
    请检查网络连接后重试。"
fi

chmod +x "$TMP_BIN"
# 兜底：清除可能的隔离属性（curl 下载通常不会打，但防御性处理，忽略失败）
xattr -d com.apple.quarantine "$TMP_BIN" 2>/dev/null || true
mv -f "$TMP_BIN" "$BIN_PATH"
trap - EXIT INT TERM
ok "已安装二进制：${BIN_PATH}"

# ── 4. 配置文件：不存在才写模板，存在则保留（避免抹掉用户已填的 key）──
if [ -f "$CONFIG_PATH" ]; then
  warn "检测到已有配置，保留不覆盖：${CONFIG_PATH}"
else
  cat > "$CONFIG_PATH" <<'TOML'
[model]
name = "gpt-4o-mini"
api_url = "https://api.openai.com/v1"
api_key = "在此填入你的 API Key（如 sk-...）"
TOML
  ok "已创建配置模板：${CONFIG_PATH}"
fi

# ── 5. 接入 PATH ─────────────────────────────────────────────
# 安装目录免 sudo，与配置同在 ~/.brainary 下（模仿 deno/bun 的做法）。
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
  info "已把 ${INSTALL_DIR} 写入 PATH：${rc_file}"
}

case "${SHELL:-}" in
  */zsh)  RC_FILE="${HOME}/.zshrc" ;;
  */bash) RC_FILE="${HOME}/.bash_profile" ;;
  *)      RC_FILE="${HOME}/.profile" ;;
esac
add_to_path "$RC_FILE"

# ── 6. 收尾提示 ──────────────────────────────────────────────
printf '\n%s✔ 安装完成！%s\n\n' "$C_GREEN$C_BOLD" "$C_RESET"
printf '  二进制： %s\n' "$BIN_PATH"
printf '  配置：   %s\n\n' "$CONFIG_PATH"
printf '%s下一步：%s\n' "$C_BOLD" "$C_RESET"
printf '  1. 编辑配置填入你的 API Key：\n'
printf '       %s$EDITOR %s%s\n' "$C_CYAN" "$CONFIG_PATH" "$C_RESET"
printf '  2. 让本次终端立即生效（或重开终端）：\n'
printf '       %sexport PATH="$HOME/.brainary/bin:$PATH"%s\n' "$C_CYAN" "$C_RESET"
printf '  3. 运行：\n'
printf '       %sbrainary --help%s\n\n' "$C_CYAN" "$C_RESET"
