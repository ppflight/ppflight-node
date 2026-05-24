#!/usr/bin/env bash
set -euo pipefail

# ppflight-node 安装入口
# 本地:  sudo bash install.sh
# 远程:  curl -fsSL https://raw.githubusercontent.com/ppflight/ppflight-node/main/install.sh | sudo bash -s -- --mode machine --panel URL --token TOKEN --machine-id 1

INSTALL_DIR="/opt/ppflight-node"
REPO_URL="https://github.com/ppflight/ppflight-node.git"
_script="${BASH_SOURCE[0]:-}"

_is_piped() {
  [[ "$_script" == /dev/fd/* || "$_script" == /proc/* || -z "$_script" ]]
}

_bootstrap() {
  [ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }
  command -v git >/dev/null 2>&1 || {
    apt-get update
    apt-get install -y git curl ca-certificates
  }
  if [ ! -f "$INSTALL_DIR/scripts/common.sh" ]; then
    echo "[bootstrap] 下载源码到 ${INSTALL_DIR}"
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 -b main "$REPO_URL" "$INSTALL_DIR"
  fi
  exec bash "$INSTALL_DIR/install.sh" "$@"
}

# curl | bash 或目录不存在时，先 clone 再执行
if _is_piped || [ ! -f "$INSTALL_DIR/scripts/common.sh" ]; then
  _bootstrap "$@"
fi

DIR="$INSTALL_DIR"
# shellcheck source=scripts/common.sh
source "$DIR/scripts/common.sh"

echo ""
echo "======== ppflight-node 安装 ========"
echo "目录: $ROOT"
echo ""

if [ $# -gt 0 ]; then
  install_with_args "$@"
else
  build_binaries
  echo ""
  run_upstream_install
  echo ""
  echo "=========================================="
  echo " 安装完成: ppflight-node"
  echo " 状态:   ppctl status"
  echo " 健康:   curl -s http://127.0.0.1:65530/healthz"
  echo " 日常控制: bash $ROOT/node.sh"
  echo "=========================================="
fi
