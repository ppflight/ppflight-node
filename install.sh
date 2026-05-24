#!/usr/bin/env bash
set -euo pipefail

# ppflight-node 安装脚本：编译 + 注册 systemd 服务
# 安装完成后日常管理请用: bash node.sh

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/common.sh
source "$DIR/scripts/common.sh"

echo ""
echo "======== ppflight-node 安装 ========"
echo "目录: $ROOT"
echo ""

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
