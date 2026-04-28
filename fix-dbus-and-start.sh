#!/bin/bash
# fix-dbus-and-start.sh
# 一键修复 D-Bus user session 并启动 hermes gateway
# Usage: curl -sL <raw-url> | bash
#   或: wget -qO- <raw-url> | bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---- 1. 安装 dbus-user-session ----
info "安装 dbus-user-session ..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq dbus-user-session

# ---- 2. 重启 user session ----
info "重启 user@0.service ..."
systemctl restart user@0.service

# ---- 3. 等待 bus socket 就绪 ----
info "等待 /run/user/0/bus ..."
for i in $(seq 1 10); do
    if [ -S /run/user/0/bus ]; then
        break
    fi
    sleep 0.5
done

if [ ! -S /run/user/0/bus ]; then
    err "/run/user/0/bus 未出现，D-Bus 可能启动失败"
    ls -la /run/user/0/ 2>/dev/null || true
    exit 1
fi

ls -la /run/user/0/bus

# ---- 4. 检查 dbus 服务状态 ----
export XDG_RUNTIME_DIR=/run/user/0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus

info "检查 dbus 用户服务 ..."
systemctl --user status dbus.service --no-pager || true

# ---- 5. 持久化环境变量 ----
info "写入环境变量到 /etc/profile.d/ ..."
cat > /etc/profile.d/dbus-user-session.sh <<'EOF'
export XDG_RUNTIME_DIR=/run/user/0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus
EOF
chmod +x /etc/profile.d/dbus-user-session.sh

# 也写到 /etc/environment（确保 cron / systemd 能读到）
grep -qX 'XDG_RUNTIME_DIR=/run/user/0' /etc/environment 2>/dev/null || echo 'XDG_RUNTIME_DIR=/run/user/0' >> /etc/environment
grep -qX 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus' /etc/environment 2>/dev/null || echo 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus' >> /etc/environment

# ---- 6. 启动 hermes gateway ----
info "启动 hermes gateway ..."
hermes gateway start

info "全部完成 ✅"
