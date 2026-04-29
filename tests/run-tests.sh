#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/hermes-dbus-fix.sh"
lib="$(mktemp)"
trap 'rm -f "$lib"' EXIT

# Source functions without executing main.
sed '/^main "\$@"$/d' "$script" > "$lib"
# shellcheck disable=SC1090
source "$lib"

assert_truthy() {
  local value="$1"
  is_truthy "$value" || {
    echo "expected truthy: $value" >&2
    exit 1
  }
}

assert_falsey() {
  local value="$1"
  if is_truthy "$value"; then
    echo "expected falsey: $value" >&2
    exit 1
  fi
}

assert_truthy 1
assert_truthy true
assert_truthy TRUE
assert_truthy yes
assert_truthy ON
assert_falsey 0
assert_falsey false
assert_falsey no
assert_falsey ''

TARGET_UID=0
unset PERSIST_ENV || true
should_persist_env

TARGET_UID=1000
unset PERSIST_ENV || true
if should_persist_env; then
  echo 'non-root target should not persist env by default' >&2
  exit 1
fi

PERSIST_ENV=1
should_persist_env
PERSIST_ENV=0
if should_persist_env; then
  echo 'PERSIST_ENV=0 should disable persistence' >&2
  exit 1
fi

TARGET_UID=1000
unset TARGET_USER || true
[ "$(target_label)" = 'uid-1000' ]
TARGET_USER=root
[ "$(target_label)" = 'root (1000)' ]

bash -n "$script"

DRY_RUN=1 START_HERMES=1 ENABLE_LINGER=0 RESTART_USER_UNIT=0 HERMES_BIN=/fake/hermes bash "$script" >/tmp/hermes-dbus-fix-dry-run-root.log

grep -q 'apt-get update -qq' /tmp/hermes-dbus-fix-dry-run-root.log
grep -q '/fake/hermes gateway start' /tmp/hermes-dbus-fix-dry-run-root.log
grep -q 'XDG_RUNTIME_DIR=/run/user/0' /tmp/hermes-dbus-fix-dry-run-root.log

DRY_RUN=1 START_HERMES=0 ENABLE_LINGER=0 RESTART_USER_UNIT=0 TARGET_UID=1000 bash "$script" >/tmp/hermes-dbus-fix-dry-run-uid.log

grep -q '目标用户：uid-1000' /tmp/hermes-dbus-fix-dry-run-uid.log
grep -q '跳过写入 /etc/environment' /tmp/hermes-dbus-fix-dry-run-uid.log
grep -q 'XDG_RUNTIME_DIR=/run/user/1000' /tmp/hermes-dbus-fix-dry-run-uid.log

rm -f /tmp/hermes-dbus-fix-dry-run-root.log /tmp/hermes-dbus-fix-dry-run-uid.log

echo 'All tests passed.'
