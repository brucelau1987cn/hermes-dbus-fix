#!/usr/bin/env bash
# Backward-compatible wrapper. Prefer ./hermes-dbus-fix.sh.
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/hermes-dbus-fix.sh" "$@"
