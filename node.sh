#!/usr/bin/env bash
set -euo pipefail

# ppflight-node 日常控制（安装完成后使用）

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/common.sh
source "$DIR/scripts/common.sh"

while true; do
  echo ""
  echo "======== ppflight-node 控制 ========"
  echo " 1) 更新源码 (pull + 编译 + 部署)"
  echo " 2) 查看状态"
  echo " 3) 用户信息 (在线 / 节点筛选 / 流量)"
  echo " 4) 实时日志"
  echo " 5) 重启服务"
  echo " 6) 修改面板地址"
  echo " 7) 修改 Token (通讯密钥)"
  echo " 8) 开启 BBR"
  echo " 0) 退出"
  read -rp "请选择: " c
  case "$c" in
    1) update_source ;;
    2) show_status; read -rp "回车继续..." _ ;;
    3) show_users ;;
    4) show_logs ;;
    5) restart_service ;;
    6) change_panel_url ;;
    7) change_token ;;
    8) enable_bbr ;;
    0) exit 0 ;;
    *) echo "无效选项" ;;
  esac
done
