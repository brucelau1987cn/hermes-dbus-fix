#!/usr/bin/env bash
# fix-dbus-and-start.sh
# Repair a systemd D-Bus user session and start hermes gateway.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/brucelau1987cn/hermes-fix/main/fix-dbus-and-start.sh | sudo bash
#   TARGET_USER=root START_HERMES=1 sudo -E bash fix-dbus-and-start.sh
#
# Environment:
#   TARGET_USER       User whose D-Bus session should be repaired. Defaults to root when run as root.
#   TARGET_UID        UID to repair. Overrides TARGET_USER lookup when set.
#   START_HERMES      Start hermes gateway after repair. Default: 1
#   HERMES_BIN        Hermes executable name/path. Default: hermes
#   HERMES_AS_TARGET  Run hermes as TARGET_USER instead of root when TARGET_UID is not 0. Default: 0
#   PERSIST_ENV       Persist D-Bus env to /etc/profile.d and /etc/environment. Default: auto (1 for root target, 0 otherwise)
#   DRY_RUN           Print commands that would change the system without running them. Default: 0
#   RESTART_USER_UNIT Restart user@UID.service. Default: 1
#   ENABLE_LINGER     Run loginctl enable-linger for the target user when available. Default: 1

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { printf '%b[INFO]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$*"; }
err() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; }
fatal() { err "$*"; exit 1; }

on_error() {
  local exit_code=$?
  err "脚本在第 ${BASH_LINENO[0]} 行失败，退出码 ${exit_code}"
  exit "$exit_code"
}
trap on_error ERR

START_HERMES="${START_HERMES:-1}"
HERMES_BIN="${HERMES_BIN:-hermes}"
HERMES_AS_TARGET="${HERMES_AS_TARGET:-0}"
DRY_RUN="${DRY_RUN:-0}"
RESTART_USER_UNIT="${RESTART_USER_UNIT:-1}"
ENABLE_LINGER="${ENABLE_LINGER:-1}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "缺少命令：$1"
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

run_cmd() {
  if is_truthy "$DRY_RUN"; then
    printf '%b[DRY-RUN]%b' "$YELLOW" "$NC"
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

require_root() {
  if is_truthy "$DRY_RUN"; then
    return
  fi

  if [ "${EUID}" -ne 0 ]; then
    fatal "请用 root 运行，例如：curl -fsSL <url> | sudo bash"
  fi
}

target_label() {
  if [ -n "${TARGET_USER:-}" ]; then
    printf '%s (%s)' "$TARGET_USER" "$TARGET_UID"
  else
    printf 'uid-%s' "$TARGET_UID"
  fi
}

detect_target() {
  if [ -n "${TARGET_UID:-}" ]; then
    if ! [[ "$TARGET_UID" =~ ^[0-9]+$ ]]; then
      fatal "TARGET_UID 必须是数字：$TARGET_UID"
    fi
    TARGET_USER="${TARGET_USER:-$(getent passwd "$TARGET_UID" | cut -d: -f1 || true)}"
    if [ -z "${TARGET_USER:-}" ]; then
      warn "UID ${TARGET_UID} 没有对应用户名；将跳过需要用户名的操作"
    fi
    return
  fi

  if [ -n "${TARGET_USER:-}" ]; then
    TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null)" || fatal "找不到用户：$TARGET_USER"
    return
  fi

  # Default to root because the common hermes failure this script fixes is
  # /run/user/0/bus missing while running the gateway as root. Non-root
  # sessions can be repaired explicitly with TARGET_USER or TARGET_UID.
  TARGET_USER="root"
  TARGET_UID="0"
}

install_dbus_user_session() {
  info "安装/确认 dbus-user-session ..."
  require_cmd apt-get
  export DEBIAN_FRONTEND=noninteractive

  if is_truthy "$DRY_RUN"; then
    run_cmd apt-get update -qq
    run_cmd apt-get install -y -qq dbus-user-session dbus
    return
  fi

  apt-get update -qq
  apt-get install -y -qq dbus-user-session dbus >/dev/null
}

enable_linger_if_possible() {
  if ! is_truthy "$ENABLE_LINGER"; then
    info "跳过 loginctl enable-linger"
    return
  fi

  if [ -z "${TARGET_USER:-}" ]; then
    warn "缺少目标用户名，跳过 enable-linger"
    return
  fi

  if command -v loginctl >/dev/null 2>&1; then
    info "启用 ${TARGET_USER} 的 linger，确保用户服务可在无登录时运行 ..."
    run_cmd loginctl enable-linger "$TARGET_USER" || warn "enable-linger 失败，继续尝试修复 D-Bus"
  else
    warn "未找到 loginctl，跳过 enable-linger"
  fi
}

restart_user_unit() {
  require_cmd systemctl

  if ! systemctl cat user@.service >/dev/null 2>&1; then
    warn "当前系统可能没有 user@.service，继续尝试检查 bus socket"
    return
  fi

  if is_truthy "$RESTART_USER_UNIT"; then
    info "重启 user@${TARGET_UID}.service ..."
    run_cmd systemctl restart "user@${TARGET_UID}.service"
  else
    info "启动/确认 user@${TARGET_UID}.service ..."
    run_cmd systemctl start "user@${TARGET_UID}.service" || true
  fi
}

wait_for_bus() {
  XDG_RUNTIME_DIR="/run/user/${TARGET_UID}"
  DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  export XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS

  if is_truthy "$DRY_RUN"; then
    info "DRY_RUN 模式：跳过等待真实 D-Bus socket"
    return
  fi

  info "等待 ${XDG_RUNTIME_DIR}/bus 就绪 ..."
  for _ in $(seq 1 30); do
    if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
      info "D-Bus socket 已就绪：${XDG_RUNTIME_DIR}/bus"
      return
    fi
    sleep 1
  done

  err "${XDG_RUNTIME_DIR}/bus 未出现，D-Bus 可能启动失败"
  ls -la "$XDG_RUNTIME_DIR" 2>/dev/null || true
  journalctl -u "user@${TARGET_UID}.service" --no-pager -n 80 2>/dev/null || true
  exit 1
}

check_user_dbus() {
  if is_truthy "$DRY_RUN"; then
    info "DRY_RUN 模式：跳过 dbus.service 状态检查"
    return
  fi

  info "检查用户 D-Bus 状态 ..."
  if [ "$TARGET_UID" = "0" ]; then
    systemctl --user status dbus.service --no-pager || warn "无法读取 dbus.service 状态，可能是系统版本使用 dbus-broker 或 socket 激活"
  elif [ -n "${TARGET_USER:-}" ] && command -v runuser >/dev/null 2>&1; then
    runuser -u "$TARGET_USER" -- env \
      XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
      DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
      systemctl --user status dbus.service --no-pager || warn "无法读取 ${TARGET_USER} 的 dbus.service 状态，可能是系统版本使用 dbus-broker 或 socket 激活"
  else
    warn "缺少目标用户名或 runuser，跳过用户 D-Bus 状态检查"
  fi
}

should_persist_env() {
  if [ -n "${PERSIST_ENV:-}" ]; then
    is_truthy "$PERSIST_ENV"
    return
  fi

  # Persisting /etc/environment is global. Keep that default only for the
  # root-target use case this script primarily fixes.
  [ "$TARGET_UID" = "0" ]
}

write_profile_env() {
  if ! should_persist_env; then
    info "跳过持久化 shell 环境变量（非 root 目标默认不写全局环境）"
    return
  fi

  local profile_file='/etc/profile.d/dbus-user-session.sh'
  info "写入 shell 环境变量：${profile_file}"
  if is_truthy "$DRY_RUN"; then
    info "DRY_RUN 模式：跳过写入 ${profile_file}"
    return
  fi

  cat > "$profile_file" <<EOF
# Generated by hermes-fix. Applies to interactive login shells.
export XDG_RUNTIME_DIR=/run/user/${TARGET_UID}
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${TARGET_UID}/bus
EOF
  chmod 0644 "$profile_file"
}

set_environment_key() {
  local key="$1"
  local value="$2"
  local env_file='/etc/environment'
  touch "$env_file"
  if grep -qE "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

write_system_environment() {
  if ! should_persist_env; then
    info "跳过写入 /etc/environment（非 root 目标默认不写全局环境）"
    return
  fi

  if is_truthy "$DRY_RUN"; then
    info "DRY_RUN 模式：跳过写入 /etc/environment"
    return
  fi

  info "写入系统环境变量：/etc/environment"
  set_environment_key 'XDG_RUNTIME_DIR' "/run/user/${TARGET_UID}"
  set_environment_key 'DBUS_SESSION_BUS_ADDRESS' "unix:path=/run/user/${TARGET_UID}/bus"
}

start_hermes_gateway() {
  if ! is_truthy "$START_HERMES"; then
    info "跳过 hermes gateway 启动"
    return
  fi

  if ! is_truthy "$DRY_RUN" && ! command -v "$HERMES_BIN" >/dev/null 2>&1; then
    fatal "未找到 ${HERMES_BIN}。请先安装 hermes，或设置 HERMES_BIN=/path/to/hermes"
  fi

  if is_truthy "$HERMES_AS_TARGET" && [ "$TARGET_UID" != "0" ]; then
    if [ -z "${TARGET_USER:-}" ]; then
      fatal "HERMES_AS_TARGET=1 需要 TARGET_USER 或可由 TARGET_UID 反查到用户名"
    fi
    require_cmd runuser
    info "以 ${TARGET_USER} 用户启动 hermes gateway ..."
    run_cmd runuser -u "$TARGET_USER" -- env \
      XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
      DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
      "$HERMES_BIN" gateway start
  else
    info "启动 hermes gateway ..."
    run_cmd "$HERMES_BIN" gateway start
  fi
}

main() {
  require_root
  detect_target

  info "目标用户：$(target_label)"
  install_dbus_user_session
  enable_linger_if_possible
  restart_user_unit
  wait_for_bus
  check_user_dbus
  write_profile_env
  write_system_environment
  start_hermes_gateway

  info "全部完成 ✅"
  info "当前环境：XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR} DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}"
}

main "$@"
