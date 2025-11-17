#!/usr/bin/env bash
set -euo pipefail

MARKER="/var/lib/saltstack/minion.installed"

install_minion() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y salt-minion
  mkdir -p "$(dirname "$MARKER")"
  touch "$MARKER"
}

if [[ ! -f "$MARKER" ]]; then
  install_minion
fi

salt-minion -l info
