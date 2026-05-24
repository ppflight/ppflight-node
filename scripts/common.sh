#!/usr/bin/env bash
# Shared helpers for install.sh and node.sh

APP_NAME="ppflight-node"
CLI_NAME="ppctl"
# 上游 installer 注册的 systemd 单元名（内部仍为此名）
SERVICE_UNIT="xboard-node"
CONFIG_DIR="/etc/xboard-node"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/xboard-node"
DIST="$ROOT/dist"
UPSTREAM_INSTALL="$SRC/install.sh"

export PATH="$PATH:/usr/local/go/bin"

REPO_URL="${PPFLIGHT_REPO_URL:-https://github.com/ppflight/ppflight-node.git}"
INSTALL_DIR="${PPFLIGHT_INSTALL_DIR:-/opt/ppflight-node}"
GO_VERSION="${PPFLIGHT_GO_VERSION:-1.26.0}"

need_root() {
  [ "$(id -u)" -eq 0 ] || { echo "请用 root 运行: sudo $*"; exit 1; }
}

arch_name() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) echo "不支持的架构: $(uname -m)"; exit 1 ;;
  esac
}

install_cli_symlinks() {
  need_root
  local A NODE_BIN CTL_BIN
  A=$(arch_name)
  binary_paths
  cp "$NODE_BIN" "/usr/local/bin/${APP_NAME}"
  cp "$CTL_BIN" "/usr/local/bin/${CLI_NAME}"
  chmod 755 "/usr/local/bin/${APP_NAME}" "/usr/local/bin/${CLI_NAME}"
  # 兼容上游 xbctl / 旧路径
  ln -sf "/usr/local/bin/${APP_NAME}" /usr/local/bin/xboard-node
  ln -sf "/usr/local/bin/${CLI_NAME}" /usr/local/bin/xbctl
  ln -sf "/usr/local/bin/${CLI_NAME}" /usr/bin/xbctl 2>/dev/null || true
}

build_binaries() {
  need_root
  [ -d "$SRC" ] || { echo "缺少目录: $SRC"; exit 1; }
  command -v go >/dev/null || { echo "未安装 Go，请先安装 /usr/local/go"; exit 1; }

  local A
  A=$(arch_name)
  mkdir -p "$DIST"
  echo "[编译] ${APP_NAME} ..."
  (cd "$SRC" && go mod download)
  (cd "$SRC" && CGO_ENABLED=0 GOOS=linux GOARCH="$A" go build -ldflags "-s -w" \
    -tags "with_quic with_utls with_wireguard with_acme with_clash_api" \
    -o "$DIST/${APP_NAME}-linux-$A" ./cmd/xboard-node)
  (cd "$SRC" && CGO_ENABLED=0 GOOS=linux GOARCH="$A" go build -ldflags "-s -w" \
    -o "$DIST/${CLI_NAME}-linux-$A" ./cmd/xbctl)
  echo "[完成] 二进制:"
  ls -lh "$DIST/${APP_NAME}-linux-$A" "$DIST/${CLI_NAME}-linux-$A"
}

binary_paths() {
  local A
  A=$(arch_name)
  NODE_BIN="$DIST/${APP_NAME}-linux-$A"
  CTL_BIN="$DIST/${CLI_NAME}-linux-$A"
}

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    return 0
  fi
  need_root
  local arch tar="/tmp/go${GO_VERSION}.tar.gz"
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "不支持的架构: $(uname -m)"; exit 1 ;;
  esac
  echo "[安装] Go ${GO_VERSION} ..."
  command -v curl >/dev/null || { apt-get update && apt-get install -y curl; }
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" -o "$tar"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tar"
  rm -f "$tar"
  export PATH="$PATH:/usr/local/go/bin"
}

ensure_repo() {
  need_root
  command -v git >/dev/null || { apt-get update && apt-get install -y git curl ca-certificates; }
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "[下载] clone $REPO_URL -> $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 -b main "$REPO_URL" "$INSTALL_DIR"
  fi
}

install_with_args() {
  need_root
  [ -d "$SRC" ] || { echo "缺少源码目录: $SRC"; exit 1; }
  [ $# -gt 0 ] || { echo "用法: install.sh --mode machine --panel URL --token TOKEN --machine-id ID"; exit 1; }

  ensure_go
  build_binaries
  binary_paths

  echo "[安装] ppflight-node (${*})"
  bash "$UPSTREAM_INSTALL" install \
    --binary "$NODE_BIN" --xbctl-binary "$CTL_BIN" \
    "$@"
  install_cli_symlinks

  echo ""
  echo "=========================================="
  echo " 安装完成: ${APP_NAME}"
  echo " 状态:   ppctl status"
  echo " 健康:   curl -s http://127.0.0.1:65530/healthz"
  echo " 管理:   bash ${INSTALL_DIR}/node.sh"
  echo "=========================================="
}

run_upstream_install() {
  need_root
  binary_paths
  [ -f "$NODE_BIN" ] || { echo "缺少二进制，请先运行: bash install.sh"; exit 1; }
  [ -f "$UPSTREAM_INSTALL" ] || { echo "缺少: $UPSTREAM_INSTALL"; exit 1; }

  echo ""
  echo "1) node 模式（单节点）"
  echo "2) machine 模式（机器）"
  read -rp "选择 [1/2]: " m
  read -rp "面板 URL: " PANEL
  local label="Machine 通讯密钥"
  [[ "$m" = "1" ]] && label="节点通讯密钥"
  read -rp "${label}: " TOKEN

  if [ "$m" = "1" ]; then
    read -rp "Node ID: " NID
    bash "$UPSTREAM_INSTALL" install --mode node \
      --panel "$PANEL" --token "$TOKEN" --node-id "$NID" \
      --binary "$NODE_BIN" --xbctl-binary "$CTL_BIN"
  else
    read -rp "Machine ID: " MID
    bash "$UPSTREAM_INSTALL" install --mode machine \
      --panel "$PANEL" --token "$TOKEN" --machine-id "$MID" \
      --binary "$NODE_BIN" --xbctl-binary "$CTL_BIN"
  fi

  install_cli_symlinks
}

upgrade_binaries() {
  build_binaries
  install_cli_symlinks
  systemctl restart "$SERVICE_UNIT"
  echo "[OK] 已升级并重启 ${APP_NAME}"
}

show_status() {
  echo "=== ${APP_NAME} 状态 ==="
  if command -v "$CLI_NAME" >/dev/null 2>&1; then
    "$CLI_NAME" status 2>/dev/null || systemctl status "$SERVICE_UNIT" --no-pager
  elif command -v xbctl >/dev/null 2>&1; then
    xbctl status 2>/dev/null || systemctl status "$SERVICE_UNIT" --no-pager
  else
    systemctl status "$SERVICE_UNIT" --no-pager
  fi
}

show_logs() {
  need_root
  echo "=== ${APP_NAME} 实时日志 (Ctrl+C 退出) ==="
  journalctl -u "$SERVICE_UNIT" -f
}

restart_service() {
  need_root
  systemctl restart "$SERVICE_UNIT"
  echo "[OK] 已重启 ${APP_NAME}"
}

change_panel_url() {
  need_root
  local CFG="${CONFIG_DIR}/config.yml"
  [ -f "$CFG" ] || { echo "未安装，找不到 $CFG"; exit 1; }
  echo "当前 panel.url:"
  grep -E '^\s*url:' "$CFG" | head -5 || true
  read -rp "新面板地址: " NEW_URL
  [ -n "$NEW_URL" ] || { echo "地址不能为空"; exit 1; }
  sed -i "0,/url:.*/s|url:.*|url: \"${NEW_URL}\"|" "$CFG"
  echo "[OK] 已更新配置（通常会自动 reload；若无反应请重启 ${APP_NAME}）"
}

mask_token() {
  local t="$1" len=${#1}
  if [ "$len" -le 8 ]; then
    echo "****"
  else
    echo "${t:0:4}****${t: -4}"
  fi
}

change_token() {
  need_root
  local CFG="${CONFIG_DIR}/config.yml"
  local CREDS="${CONFIG_DIR}/credentials.env"
  [ -f "$CFG" ] || { echo "未安装，找不到 $CFG"; return 1; }
  [ -f "$CREDS" ] || { echo "找不到 $CREDS"; return 1; }

  local -a ENV_KEYS=()
  while IFS= read -r line; do
    key=$(echo "$line" | sed 's/.*token_env:[[:space:]]*//' | tr -d ' "'"'")
    [ -n "$key" ] && ENV_KEYS+=("$key")
  done < <(grep -E 'token_env:' "$CFG" | sort -u)

  if [ "${#ENV_KEYS[@]}" -eq 0 ]; then
    echo "config 中未找到 token_env"
    return 1
  fi

  local key="${ENV_KEYS[0]}"
  if [ "${#ENV_KEYS[@]}" -gt 1 ]; then
    echo "检测到多个 Token 配置:"
    local i=1
    for k in "${ENV_KEYS[@]}"; do
      echo "  $i) $k"
      i=$((i + 1))
    done
    read -rp "选择要修改的 [1-${#ENV_KEYS[@]}]: " pick
    [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#ENV_KEYS[@]}" ] || {
      echo "无效选择"; return 1
    }
    key="${ENV_KEYS[$((pick - 1))]}"
  fi

  local old=""
  old=$(grep -E "^${key}=" "$CREDS" 2>/dev/null | head -1 | cut -d= -f2- || true)
  if [ -n "$old" ]; then
    echo "当前 Token: $(mask_token "$old")"
  else
    echo "当前未设置 ${key}"
  fi

  local label="节点通讯密钥"
  [[ "$key" == *"_MACHINE_TOKEN" ]] && label="Machine 通讯密钥"

  read -rsp "新 ${label}: " NEW_TOKEN
  echo
  [ -n "$NEW_TOKEN" ] || { echo "Token 不能为空"; return 1; }

  local tmp found=0
  tmp=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "${key}="* ]]; then
      echo "${key}=${NEW_TOKEN}"
      found=1
    else
      echo "$line"
    fi
  done < "$CREDS" > "$tmp"
  if [ "$found" -eq 0 ]; then
    echo "${key}=${NEW_TOKEN}" >> "$tmp"
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$CREDS"

  systemctl restart "$SERVICE_UNIT"
  echo "[OK] Token 已更新并已重启 ${APP_NAME}"
}

bbr_is_enabled() {
  local cc qdisc
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
  qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "")
  [ "$cc" = "bbr" ] && [ "$qdisc" = "fq" ]
}

show_bbr_status() {
  local cc qdisc mod
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
  mod=$(lsmod 2>/dev/null | grep -c 'tcp_bbr' || true)
  echo "  tcp_congestion_control = $cc"
  echo "  default_qdisc          = $qdisc"
  echo "  tcp_bbr 模块           = $([ "$mod" -gt 0 ] && echo 已加载 || echo 未加载)"
  if bbr_is_enabled; then
    echo "  状态                   = 已开启 BBR"
  else
    echo "  状态                   = 未开启 (当前: ${cc}/${qdisc})"
  fi
}

enable_bbr() {
  need_root
  echo "=== TCP BBR 状态 ==="
  show_bbr_status
  echo ""
  if bbr_is_enabled; then
    echo "[OK] BBR 已是开启状态"
    read -rp "回车继续..." _
    return 0
  fi
  read -rp "是否开启 BBR? [y/N]: " ans
  [[ "$ans" =~ ^[yY]$ ]] || { echo "已取消"; return 0; }

  modprobe tcp_bbr 2>/dev/null || true
  sysctl -w net.core.default_qdisc=fq
  sysctl -w net.ipv4.tcp_congestion_control=bbr

  local SYSCTL_CONF="/etc/sysctl.conf"
  touch "$SYSCTL_CONF"
  grep -q '^net\.core\.default_qdisc=fq' "$SYSCTL_CONF" 2>/dev/null || \
    echo 'net.core.default_qdisc=fq' >> "$SYSCTL_CONF"
  grep -q '^net\.ipv4\.tcp_congestion_control=bbr' "$SYSCTL_CONF" 2>/dev/null || \
    echo 'net.ipv4.tcp_congestion_control=bbr' >> "$SYSCTL_CONF"

  if [ -d /etc/modules-load.d ]; then
    echo tcp_bbr > /etc/modules-load.d/bbr.conf
  fi

  echo ""
  echo "=== 开启后 ==="
  show_bbr_status
  if bbr_is_enabled; then
    echo "[OK] BBR 已开启（重启后仍有效）"
  else
    echo "[WARN] 开启失败，请确认内核 >= 4.9 且支持 tcp_bbr"
  fi
  read -rp "回车继续..." _
}

health_port() {
  local port=65530
  local CFG="${CONFIG_DIR}/config.yml"
  if [ -f "$CFG" ]; then
    local p
    p=$(grep -m1 'health_port:' "$CFG" 2>/dev/null | sed 's/.*health_port:[[:space:]]*//' | tr -cd '0-9')
    [ -n "$p" ] && port="$p"
  fi
  echo "$port"
}

update_source() {
  need_root
  echo "[1/3] 拉取源码 ..."
  if [ -d "$ROOT/.git" ]; then
    git -C "$ROOT" pull || { echo "git pull 失败"; return 1; }
  else
    echo "未关联 git 仓库，跳过 pull"
  fi
  echo "[2/3] 编译 ..."
  build_binaries
  echo "[3/3] 部署并重启 ..."
  install_cli_symlinks
  systemctl restart "$SERVICE_UNIT"
  sleep 2
  if curl -fsS --max-time 3 "http://127.0.0.1:$(health_port)/healthz" >/dev/null 2>&1; then
    echo "[OK] 更新完成，${APP_NAME} 运行正常"
  else
    echo "[WARN] 已更新但 health 检查未通过，请选「实时日志」排查"
  fi
}

show_users() {
  local port url
  port=$(health_port)
  url="http://127.0.0.1:${port}/stats"
  echo "=== ${APP_NAME} 用户信息 ==="
  if ! curl -fsS --max-time 5 "$url" -o /tmp/ppflight-stats.json 2>/dev/null; then
    echo "无法获取用户统计（服务未运行或需先「更新源码」编译新版本）"
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "需要 python3 来格式化输出，原始 JSON:"
    cat /tmp/ppflight-stats.json
    return 0
  fi
  python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/ppflight-stats.json").read_text())
nodes = data.get("nodes") or []
if not nodes:
    print("暂无节点数据（可能还没有用户连接）")
    raise SystemExit(0)

def fmt_bytes(n):
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.2f} {unit}"
        n /= 1024

def fmt_speed(bps):
    return fmt_bytes(bps) + "/s"

total_up = total_down = total_online = 0
for node in nodes:
    nid = node.get("node_id")
    proto = node.get("protocol") or "-"
    port = node.get("port") or "-"
    print(f"\n--- Node {nid} ({proto}:{port}) ---")
    print(f"连接数: {node.get('active_connections', 0)}  在线用户: {node.get('online_user_count', 0)}")
    print(f"速率  上传: {fmt_speed(node.get('upload_speed_bps', 0))}  下载: {fmt_speed(node.get('download_speed_bps', 0))}")
    users = node.get("users") or []
    if not users:
        print("(无用户流量记录)")
        continue
    print(f"{'':1}{'UID':<6}{'在线':<6}{'上传(待上报)':<16}{'下载(待上报)':<16}UUID")
    for u in sorted(users, key=lambda x: x.get("user_id", 0)):
        uid = u.get("user_id", 0)
        online = u.get("online_devices", 0)
        up = u.get("upload_bytes", 0)
        down = u.get("download_bytes", 0)
        uuid = u.get("uuid") or "-"
        mark = "*" if online > 0 else " "
        total_up += up
        total_down += down
        if online > 0:
            total_online += 1
        print(f"{mark}{uid:<5}{online:<6}{fmt_bytes(up):<16}{fmt_bytes(down):<16}{uuid}")
print(f"\n合计 在线用户: {total_online}  上传: {fmt_bytes(total_up)}  下载: {fmt_bytes(total_down)}")
print("(* 当前在线  流量为距上次上报面板前的累计值)")
PY
  read -rp "回车继续..." _
}
