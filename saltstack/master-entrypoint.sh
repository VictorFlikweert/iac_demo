#!/usr/bin/env bash
set -euo pipefail

MARKER="/var/lib/saltstack/master.installed"

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
