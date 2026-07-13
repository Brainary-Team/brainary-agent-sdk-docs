#!/usr/bin/env bash
# 启动 / 停止 Brainary 整站 dev（官网 + 文档，单源，体验对齐 build）
#
# 一条命令同时拉起两个 dev server，并用「dev 期单源反向代理」让它们对外表现成
# 一个站——和 build 后的产物同构：
#   官网（website/，Vite）        → /        （前门，统一入口）
#   文档（user_docs/，VitePress） → /docs/   （由官网 dev 反代到文档 dev）
# 于是官网里写死的 <a href="/docs/"> 在 dev 也能正常跳（不再命中官网自身端口 404）。
#
# 用法：
#   ./start-docs.sh          后台启动整站，就绪后自动开浏览器到统一入口，交还终端
#   ./start-docs.sh -f       前台启动，同屏流式打印两边日志，Ctrl+C 一并停止
#   ./start-docs.sh stop     停止后台运行的整站（官网 + 文档都停）
#
# 可选环境变量：
#   DOCS_PORT   文档 dev 起始端口（默认 5173），被占用时自动顺延
#   WEB_PORT    官网 dev 起始端口（默认 5174），被占用时自动顺延
#
# 停止方式：
#   1) 前台运行时直接按 Ctrl+C；
#   2) 任意终端执行 ./start-docs.sh stop。
set -euo pipefail

# 脚本所在目录 = 仓库根；官网在 website/，文档在 user_docs/
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$ROOT_DIR/user_docs"
WEB_DIR="$ROOT_DIR/website"

# 两个服务各自的运行态文件（pid=进程组 / port=实际端口，供 stop 兜底 / log=后台日志）
DOCS_PIDFILE="$ROOT_DIR/.docs-dev.pid"
DOCS_PORTFILE="$ROOT_DIR/.docs-dev.port"
DOCS_LOG="$ROOT_DIR/.docs-dev.log"
WEB_PIDFILE="$ROOT_DIR/.web-dev.pid"
WEB_PORTFILE="$ROOT_DIR/.web-dev.port"
WEB_LOG="$ROOT_DIR/.web-dev.log"

HOST="127.0.0.1"   # 见下方端口选择处的 IPv4/IPv6 说明
MAX_TRIES=50

# 就绪探测总时长（秒）。默认 90s：冷启动 + Vite 首次「重新优化依赖」(改过 vite.config
# 后的首启会触发)叠加冷编译，30s 往往不够，慢机器/慢盘更甚。可用 READY_TIMEOUT 覆盖。
READY_TIMEOUT="${READY_TIMEOUT:-90}"

# ---------- 环境自动检测 ----------
# 端口探测与进程组终止在 macOS / Linux 上都需可用：
#   - 进程组：统一用 bash job control（set -m），两平台一致，无需 setsid（macOS 无此命令）
#   - 端口探测：优先 lsof（两平台自带），Linux 回退 ss，最后回退 nc
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) PLATFORM="macOS" ;;
  Linux)  PLATFORM="Linux" ;;
  *)      PLATFORM="$(uname -s 2>/dev/null || echo unknown)" ;;
esac

# ---------- 停止逻辑 ----------
# 停单个服务：进程组终止（+ verify/SIGKILL 升级）+ 端口兜底 + 清理运行态文件。
# 为什么要 verify+升级：dev server 可能已僵死（能 accept 连接却不回响应，页面一片
# 空白），SIGTERM 未必奏效。为什么要端口兜底：进程组可能已成孤儿（组长先死、node
# 子进程被 init 收养并改了组），负号 kill 打不到，只能凭记录的端口清 LISTEN 占用者。
stop_one() {
  local pidfile="$1" portfile="$2" logfile="$3" label="$4"
  if [ -f "$pidfile" ]; then
    local pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      echo "停止${label}（进程组 ${pid}）…"
      kill -TERM "-${pid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      local waited=0
      while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 5 ]; do
        sleep 1
        waited=$((waited + 1))
      done
      if kill -0 "$pid" 2>/dev/null; then
        echo "${label}未在 ${waited}s 内退出，强制终止（SIGKILL）…"
        kill -KILL "-${pid}" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
  fi
  local port
  port="$(cat "$portfile" 2>/dev/null || true)"
  if [ -n "${port:-}" ] && command -v lsof >/dev/null 2>&1; then
    local holders
    holders="$(lsof -tiTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null || true)"
    if [ -n "$holders" ]; then
      echo "端口 ${port}（${label}）仍被占用，清理残留监听进程…"
      # shellcheck disable=SC2086
      kill -TERM $holders 2>/dev/null || true
      sleep 1
      holders="$(lsof -tiTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null || true)"
      # shellcheck disable=SC2086
      [ -n "$holders" ] && kill -KILL $holders 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile" "$portfile" "$logfile"
  return 0
}

stop_server() {
  if [ ! -f "$DOCS_PIDFILE" ] && [ ! -f "$WEB_PIDFILE" ]; then
    echo "未发现运行中的服务（无 pid 文件）。"
    return 0
  fi
  stop_one "$DOCS_PIDFILE" "$DOCS_PORTFILE" "$DOCS_LOG" "文档站"
  stop_one "$WEB_PIDFILE"  "$WEB_PORTFILE"  "$WEB_LOG"  "官网"
}

# ---------- 参数解析 ----------
# 无参数 → 后台启动（默认，不占前台）；-f → 前台启动（实时日志、Ctrl+C 停）；stop → 停止。
FOREGROUND=0
case "${1:-}" in
  stop)
    stop_server
    exit 0
    ;;
  -f|--foreground|foreground)
    FOREGROUND=1
    ;;
  "")
    : # 后台模式（默认）
    ;;
  *)
    echo "未知参数：$1" >&2
    echo "用法：./start-docs.sh [stop|-f]" >&2
    echo "  （无参数）后台启动整站并自动打开浏览器；-f 前台启动；stop 停止。" >&2
    exit 2
    ;;
esac

# ---------- 依赖检查 ----------
hint_install_node() {
  echo "  未检测到 Node.js。VitePress / Vite 需要 Node.js（建议 18 LTS 及以上）。" >&2
  if [ "$PLATFORM" = "macOS" ]; then
    echo "  安装方式（任选其一）：" >&2
    echo "    • Homebrew:  brew install node" >&2
    echo "    • 官网下载:  https://nodejs.org/（选 LTS）" >&2
    echo "    • nvm:       https://github.com/nvm-sh/nvm 然后 nvm install --lts" >&2
  else
    echo "  安装方式（任选其一）：" >&2
    echo "    • Debian/Ubuntu:  sudo apt-get install -y nodejs npm" >&2
    echo "    • Fedora/RHEL:    sudo dnf install -y nodejs npm" >&2
    echo "    • Arch:           sudo pacman -S nodejs npm" >&2
    echo "    • nvm（推荐）:    https://github.com/nvm-sh/nvm 然后 nvm install --lts" >&2
    echo "    • 官网下载:       https://nodejs.org/（选 LTS）" >&2
  fi
}

# 1) node
if ! command -v node >/dev/null 2>&1; then
  echo "错误：缺少依赖 node。" >&2
  hint_install_node
  exit 1
fi

# 2) pnpm（项目使用 pnpm，有 pnpm-lock.yaml）
if ! command -v pnpm >/dev/null 2>&1; then
  echo "错误：未检测到 pnpm（项目依赖 pnpm 管理）。" >&2
  echo "  安装方式（任选其一）：" >&2
  echo "    • npm:  npm install -g pnpm" >&2
  echo "    • curl: curl -fsSL https://get.pnpm.io/install.sh | sh -" >&2
  echo "    • brew: brew install pnpm" >&2
  echo "  安装完成后重新运行 ./start-docs.sh。" >&2
  exit 1
fi

# 3) Node 主版本 >= 18
NODE_MAJOR="$(node -v 2>/dev/null | sed -E 's/^v?([0-9]+).*/\1/')"
if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
  echo "错误：Node.js 版本过低（当前 $(node -v)），需要 18 及以上。" >&2
  hint_install_node
  exit 1
fi

# 4) 文档与官网目录 / package.json
for pair in "$DOCS_DIR|文档 user_docs" "$WEB_DIR|官网 website"; do
  dir="${pair%%|*}"; name="${pair##*|}"
  if [ ! -d "$dir" ]; then
    echo "错误：未找到${name}目录 ${dir}。请确认脚本位于仓库根目录。" >&2
    exit 1
  fi
  if [ ! -f "$dir/package.json" ]; then
    echo "错误：未找到 ${dir}/package.json。" >&2
    exit 1
  fi
done

# 5) 依赖是否已安装（分别检查 vitepress / vite）
if [ ! -d "$DOCS_DIR/node_modules" ] || [ ! -d "$DOCS_DIR/node_modules/vitepress" ]; then
  echo "错误：文档站依赖未安装（缺少 ${DOCS_DIR}/node_modules）。" >&2
  echo "    cd \"${DOCS_DIR}\" && pnpm install" >&2
  exit 1
fi
if [ ! -d "$WEB_DIR/node_modules" ] || [ ! -d "$WEB_DIR/node_modules/vite" ]; then
  echo "错误：官网依赖未安装（缺少 ${WEB_DIR}/node_modules）。" >&2
  echo "    cd \"${WEB_DIR}\" && pnpm install" >&2
  exit 1
fi

# ---------- 启动前：若已有实例在跑，先提示 ----------
for pf in "$DOCS_PIDFILE" "$WEB_PIDFILE"; do
  if [ -f "$pf" ]; then
    old="$(cat "$pf" 2>/dev/null || true)"
    if [ -n "${old:-}" ] && kill -0 "$old" 2>/dev/null; then
      echo "已有服务在运行（进程组 ${old}，见 ${pf}）。先执行 ./start-docs.sh stop 再启动。"
      exit 1
    fi
  fi
done
rm -f "$DOCS_PIDFILE" "$DOCS_PORTFILE" "$WEB_PIDFILE" "$WEB_PORTFILE"   # 清残留的过期文件

# PID 文件所在目录需可写
if [ ! -w "$ROOT_DIR" ]; then
  echo "错误：目录不可写，无法记录 PID 文件：${ROOT_DIR}" >&2
  exit 1
fi

# ---------- 端口选择 ----------
# 绑 IPv4 回环 127.0.0.1 而非主机名 localhost：macOS 上 `--host localhost` 会让 Node
# 只绑到 IPv6 [::1]，而浏览器解析 localhost 常优先拿到 IPv4 127.0.0.1 → 连到没人监听的
# IPv4 口 → 连接被拒 / 页面空白。直接绑 127.0.0.1 彻底消除 IPv4/IPv6 错配。
PORT_TOOL=""
if command -v lsof >/dev/null 2>&1; then
  PORT_TOOL="lsof"
elif command -v ss >/dev/null 2>&1; then
  PORT_TOOL="ss"
elif command -v nc >/dev/null 2>&1; then
  PORT_TOOL="nc"
fi
if [ -z "$PORT_TOOL" ]; then
  echo "提示：未找到 lsof/ss/nc，无法预检端口占用；将直接尝试默认端口（dev server 自身也会顺延）。"
fi

port_in_use() {
  local port="$1"
  case "$PORT_TOOL" in
    lsof) lsof -iTCP:"$port" -sTCP:LISTEN -Pn >/dev/null 2>&1 ;;
    ss)   ss -ltn 2>/dev/null | grep -q ":${port}[[:space:]]" ;;
    nc)   nc -z "$HOST" "$port" >/dev/null 2>&1 ;;
    *)    return 1 ;;   # 无可用工具时，默认认为端口空闲
  esac
}

# 从 <起始端口> 起找第一个空闲端口（跳过 <排除端口>，用于避免两服务撞同一口）。
# 进度提示走 stderr，最终选定端口 printf 到 stdout 供调用方捕获。
find_free_port() {
  local start="$1" skip="${2:-}" port tries=0
  if ! printf '%s' "$start" | grep -qE '^[0-9]+$' || [ "$start" -lt 1 ] || [ "$start" -gt 65535 ]; then
    echo "错误：起始端口非法（${start}），应为 1–65535 的整数。" >&2
    return 2
  fi
  port="$start"
  while port_in_use "$port" || [ "$port" = "$skip" ]; do
    [ "$port" = "$skip" ] || echo "端口 ${port} 已被占用，尝试下一个…" >&2
    port=$((port + 1))
    tries=$((tries + 1))
    if [ "$port" -gt 65535 ]; then
      echo "错误：端口已超出 65535，放弃。" >&2
      return 1
    fi
    if [ "$tries" -ge "$MAX_TRIES" ]; then
      echo "错误：从 ${start} 起连续 ${MAX_TRIES} 个端口都被占用，放弃。" >&2
      return 1
    fi
  done
  printf '%s' "$port"
}

DOCS_PORT="$(find_free_port "${DOCS_PORT:-5173}")"          || exit 1
WEB_PORT="$(find_free_port "${WEB_PORT:-5174}" "$DOCS_PORT")" || exit 1

# 对外统一入口（前门 = 官网 dev；/docs/ 经代理转发到文档 dev）。
# 一律带尾斜杠：/docs（无斜杠）在 VitePress 下会 404，自动打开与探测都用带斜杠地址。
FRONT_URL="http://${HOST}:${WEB_PORT}/"
DOCS_URL="http://${HOST}:${WEB_PORT}/docs/"
DOCS_OWN_URL="http://${HOST}:${DOCS_PORT}/docs/"   # 文档自己的端口（直连，不经代理）

# ---------- 就绪探测 & 打开浏览器 ----------
# 为什么要探测：dev server 冷启动约 1~2s 才返回首个 200，Vite 首次请求还要按需编译。
# 过早打开会落在空窗期 → 连接被拒 / 空白。这里轮询直到真正 200（顺带预热首次编译），
# 再打印地址 / 开浏览器。任一被监视进程中途退出则提前止损，不空等。
# 每 ~10s 打一次心跳，避免慢冷启动时终端看着「卡死无输出」。
# 用法：wait_until_ready <url> <timeout_secs> <label> <watch_pid...>
wait_until_ready() {
  local url="$1" timeout="$2" label="$3"; shift 3
  local watch_pids=("$@")
  if ! command -v curl >/dev/null 2>&1; then
    echo "（未找到 curl，无法精确探测就绪；等待 3s 后继续）"
    sleep 3
    return 0
  fi
  local i code p tries=$(( timeout * 2 ))   # 每轮 0.5s
  for i in $(seq 1 "$tries"); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$url" 2>/dev/null || echo 000)"
    [ "$code" = "200" ] && return 0
    for p in "${watch_pids[@]}"; do
      kill -0 "$p" 2>/dev/null || return 1
    done
    if [ "$(( i % 20 ))" -eq 0 ]; then
      echo "  …仍在等待${label}就绪（已 $(( i / 2 ))s / 上限 ${timeout}s）" >&2
    fi
    sleep 0.5
  done
  return 1
}

open_browser() {
  local url="$1" opener=""
  if [ "$PLATFORM" = "macOS" ] && command -v open >/dev/null 2>&1; then
    opener="open"
  elif command -v xdg-open >/dev/null 2>&1; then
    opener="xdg-open"
  fi
  if [ -n "$opener" ]; then
    "$opener" "$url" >/dev/null 2>&1 || true
  else
    echo "（未找到浏览器打开命令，请手动访问上面的地址）"
  fi
}

# ---------- 启动两个 dev server ----------
# 以独立进程组启动，便于整组终止（set -m：后台任务自成进程组，PID==PGID，macOS/Linux 通用）。
# 直接 `pnpm --dir <目录> exec <bin>`：避开 npm script 里写死的端口，让 --host/--port/
# --strictPort 正确送达（不要用 `pnpm run xxx -- --flag`，pnpm 会把 `--` 原样透传致 flag 失效）。
# --strictPort：端口已由上面的扫描选定，禁止 dev server 再自行顺延，保证监听端口与打印地址一致。
#
# 单源关键的两个环境变量（仅 dev 生效，不影响 build）：
#   DOCS_PROXY_TARGET   → 官网 vite.config.js 据此把 /docs 反代到文档 dev
#   DOCS_HMR_CLIENT_PORT → 文档 vitepress 据此让 HMR ws 直连自身端口，避开与官网 Vite 的 HMR 冲突
: > "$DOCS_LOG"; : > "$WEB_LOG"   # 先建空日志文件，供前台 tail -f

# stdin 必须来自 /dev/null（`</dev/null`）——这是本脚本能在交互式终端后台跑的关键：
# VitePress / Vite dev 会开「交互式按键」监听（日志里的 “press h to show help”），
# 即读取终端 stdin。而我们用 `set -m` 让每个服务自成进程组、在后台运行；后台进程组
# 一旦读控制终端，内核发 SIGTTIN 把整组挂起（STAT=T、0% CPU、端口已 LISTEN 却不 accept、
# 连 TCP 握手都超时）——正是“终端卡住、页面空白”的根因。把 stdin 接到 /dev/null 后，
# 按键读取立刻拿到 EOF、退出交互模式，永不碰终端，也就永不 SIGTTIN。
# （nohup 在本机 bash+job control 下并未把 stdin 改到 /dev/null，故这里显式重定向。）
start_docs_bg() {
  DOCS_HMR_CLIENT_PORT="$DOCS_PORT" \
    nohup pnpm --dir "$DOCS_DIR" exec vitepress dev --host "$HOST" --port "$DOCS_PORT" --strictPort \
    </dev/null >"$DOCS_LOG" 2>&1 &
  DOCS_PID=$!
  echo "$DOCS_PID" > "$DOCS_PIDFILE"
  echo "$DOCS_PORT" > "$DOCS_PORTFILE"
}

start_web_bg() {
  DOCS_PROXY_TARGET="http://${HOST}:${DOCS_PORT}" \
    nohup pnpm --dir "$WEB_DIR" exec vite --host "$HOST" --port "$WEB_PORT" --strictPort \
    </dev/null >"$WEB_LOG" 2>&1 &
  WEB_PID=$!
  echo "$WEB_PID" > "$WEB_PIDFILE"
  echo "$WEB_PORT" > "$WEB_PORTFILE"
}

# 文档自愈重启：结束当前文档进程组 + 端口兜底清理，再以同端口重新拉起。
# 用于「已监听但事件循环卡死（0% CPU、不 accept 连接）」这类冷启动偶发僵死——
# 观察到 VitePress 偶尔起来后 banner 已打印却连不上。文档端口不变（仍 DOCS_PORT），
# 官网代理目标随之不变，重启文档对代理透明、安全。
restart_docs() {
  kill -TERM "-${DOCS_PID}" 2>/dev/null || kill -TERM "$DOCS_PID" 2>/dev/null || true
  if command -v lsof >/dev/null 2>&1; then
    local h
    h="$(lsof -tiTCP:"$DOCS_PORT" -sTCP:LISTEN -Pn 2>/dev/null || true)"
    # shellcheck disable=SC2086
    [ -n "$h" ] && { kill -KILL $h 2>/dev/null || true; }
  fi
  sleep 1
  set -m
  start_docs_bg   # 重置全局 DOCS_PID，指向新进程组
  set +m
  disown -a 2>/dev/null || true
}

# 整站就绪 = 三步都过。刻意先等「文档自己端口」直连就绪，再验官网、再验代理转发：
# 这样代理首次被打时文档已在监听，从根上避免启动期 /docs/ 的 ECONNREFUSED 噪声。
# 冷启动(尤其改过 vite.config 触发 Vite 重新优化依赖)较慢，READY_TIMEOUT 已放宽到 90s。
# 第一关给一个较短的宽限窗口：窗口内文档端口没通、但进程还活着，判为疑似冷启动僵死，
# 自动重启文档一次再等满 READY_TIMEOUT——把偶发卡死从「硬失败」变成「自愈」。
wait_site_ready() {
  # 宽限窗口默认 = READY_TIMEOUT/3（下限 20s）；可用 READY_GRACE 覆盖（慢机器/测试用）。
  local grace="${READY_GRACE:-$(( READY_TIMEOUT / 3 ))}"
  [ "$grace" -lt 20 ] && [ -z "${READY_GRACE:-}" ] && grace=20
  if ! wait_until_ready "$DOCS_OWN_URL" "$grace" "文档" "$DOCS_PID" "$WEB_PID"; then
    if kill -0 "$DOCS_PID" 2>/dev/null; then
      echo "文档 dev 已监听却 ${grace}s 内无响应（疑似冷启动卡死），自动重启一次…" >&2
      restart_docs
    fi
    wait_until_ready "$DOCS_OWN_URL" "$READY_TIMEOUT" "文档" "$DOCS_PID" "$WEB_PID" || return 1
  fi
  wait_until_ready "$FRONT_URL" "$READY_TIMEOUT" "官网" "$DOCS_PID" "$WEB_PID" || return 1
  wait_until_ready "$DOCS_URL"  "$READY_TIMEOUT" "代理" "$DOCS_PID" "$WEB_PID" || return 1
}

echo ""
echo "环境：${PLATFORM}（Node $(node -v)）"
echo "启动整站：官网 :${WEB_PORT} + 文档 :${DOCS_PORT}（文档经代理挂在 /docs/）…"

set -m
start_docs_bg
start_web_bg
set +m

if [ "$FOREGROUND" = "1" ]; then
  # ── 前台模式（-f）：同屏流式两边日志、Ctrl+C 一并停 ──
  cleanup() {
    echo ""
    echo "正在停止整站…"
    kill -TERM "-${DOCS_PID}" 2>/dev/null || kill -TERM "$DOCS_PID" 2>/dev/null || true
    kill -TERM "-${WEB_PID}"  2>/dev/null || kill -TERM "$WEB_PID"  2>/dev/null || true
    rm -f "$DOCS_PIDFILE" "$DOCS_PORTFILE" "$WEB_PIDFILE" "$WEB_PORTFILE"
    exit 0
  }
  trap cleanup INT TERM

  # 后台等就绪再开浏览器（不阻塞前台日志流）
  ( wait_site_ready && {
      echo ""
      echo "整站已就绪：➜  ${FRONT_URL}   （文档在 ${DOCS_URL}）"
      open_browser "$FRONT_URL"
    } ) &

  echo "（前台运行，实时日志如下；按 Ctrl+C 停止整站）"
  # 同屏跟随两边日志，直到收到信号由 cleanup 收尾
  tail -n +1 -f "$DOCS_LOG" "$WEB_LOG"
  exit 0
fi

# ── 后台模式（默认，不占前台）──
disown -a 2>/dev/null || true   # 脱离 job 表；配合 nohup，关终端也不影响服务

echo "等待整站就绪…"
if wait_site_ready; then
  echo ""
  echo "整站已就绪（统一入口，多数终端可直接点击）："
  echo "  ➜  官网首页  ${FRONT_URL}"
  echo "  ➜  SDK 文档  ${DOCS_URL}"
  echo "已在后台运行（日志：${DOCS_LOG} / ${WEB_LOG}）。终端可继续使用。"
  echo "停止：另开终端执行 ./start-docs.sh stop"
  open_browser "$FRONT_URL"
  exit 0
else
  echo "错误：整站在约 ${READY_TIMEOUT}s 内未就绪（或某个服务已崩溃）。" >&2
  echo "  提示：若日志末尾是 “Re-optimizing dependencies …”，多为冷启动首次依赖优化偏慢，" >&2
  echo "        可重试，或用更大的超时：READY_TIMEOUT=180 ./start-docs.sh" >&2
  sleep 1   # 给两边缓冲区一点时间把 banner/报错 flush 到日志，避免下面 tail 看着是空的
  echo "最近文档日志（${DOCS_LOG}）：" >&2
  tail -n 25 "$DOCS_LOG" 2>/dev/null >&2 || true
  echo "最近官网日志（${WEB_LOG}）：" >&2
  tail -n 25 "$WEB_LOG" 2>/dev/null >&2 || true
  # 收掉可能半死的两个进程组，避免占端口拖累下次启动
  kill -TERM "-${DOCS_PID}" 2>/dev/null || kill -TERM "$DOCS_PID" 2>/dev/null || true
  kill -TERM "-${WEB_PID}"  2>/dev/null || kill -TERM "$WEB_PID"  2>/dev/null || true
  rm -f "$DOCS_PIDFILE" "$DOCS_PORTFILE" "$WEB_PIDFILE" "$WEB_PORTFILE"
  exit 1
fi
