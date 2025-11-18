#!/usr/bin/env bash
set -euo pipefail

MARKER="/var/lib/saltstack/master.installed"
CUSTOM_RETURNERS_DIR="/srv/salt/_returners"
EXT_RETURNERS_DIR="/var/cache/salt/master/extmods/returners"

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y salt-master salt-minion
  mkdir -p "$(dirname "$MARKER")"
  touch "$MARKER"
}

if [[ ! -f "$MARKER" ]]; then
  install_packages
fi

sync_returners() {
  if [[ -d "$CUSTOM_RETURNERS_DIR" ]]; then
    mkdir -p "$EXT_RETURNERS_DIR"
    if cp -a "$CUSTOM_RETURNERS_DIR"/. "$EXT_RETURNERS_DIR"/ 2>/dev/null; then
      echo "Synced custom returners from $CUSTOM_RETURNERS_DIR to $EXT_RETURNERS_DIR"
    else
      echo "Failed to sync custom returners (directory may be empty)" >&2
    fi
  fi
}

sync_returners

salt-master -l info &
MASTER_PID=$!

salt-minion -l info &
MINION_PID=$!

cleanup() {
  for pid in "$MINION_PID" "$MASTER_PID"; do
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      echo "Stopping process $pid..."
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

wait -n "$MASTER_PID" "$MINION_PID"
