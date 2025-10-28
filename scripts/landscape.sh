#!/usr/bin/env bash
set -euo pipefail

CMD_NAME="$(basename "$0")"
COMPOSE=(docker compose)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$REPO_ROOT/landscape/state/state.json"
BROADCAST_SOURCE="$REPO_ROOT/landscape/state/broadcasts/panelpc-note.txt"
CONTROLLER="landscape-controller"
NODES=(landscape-panelpc landscape-qg-1 landscape-qg-2)
SERVICES=("$CONTROLLER" "${NODES[@]}")

container_running() {
  local svc="$1"
  [[ -n "$(${COMPOSE[@]} ps --status=running -q "$svc" 2>/dev/null)" ]]
}

ensure_running() {
  local svc="$1"
  if ! container_running "$svc"; then
    "${COMPOSE[@]}" up -d "$svc"
  fi
}

wait_for_controller() {
  ensure_running "$CONTROLLER"
  local attempts=0
  local max_attempts=15
  local delay=2
  while (( attempts < max_attempts )); do
    if "${COMPOSE[@]}" exec "$CONTROLLER" curl -fsS "http://localhost:8028/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
    attempts=$((attempts + 1))
  done
  echo "Landscape controller is not ready after $((max_attempts * delay)) seconds" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $CMD_NAME <command> [args...]

Commands:
  start                        Start the Landscape controller and agents
  stop                         Stop all Landscape containers
  status                       Show Landscape container status
  shell [SERVICE] [CMD]        Open a shell (default: bash) inside a service
  reconcile [NODE]             Trigger an immediate agent converge (default: all nodes)
  topology NODE GROUP          Assign NODE to a Landscape group and persist state
  broadcast [FILE|-]           Show or replace the PanelPC broadcast seed file
  state [NODE]                 Fetch rendered desired state from the controller (default: all nodes)
EOF
}

ensure_service() {
  local target="$1"
  for svc in "${SERVICES[@]}"; do
    if [[ "$svc" == "$target" ]]; then
      return 0
    fi
  done
  echo "Unknown service: $target" >&2
  exit 1
}

ensure_node() {
  local target="$1"
  for node in "${NODES[@]}"; do
    if [[ "$node" == "$target" ]]; then
      return 0
    fi
  done
  echo "Unknown Landscape node: $target" >&2
  exit 1
}

require_args() {
  local count="$1"
  shift
  if [[ "$#" -lt "$count" ]]; then
    usage
    exit 1
  fi
}

command_start() {
  "${COMPOSE[@]}" up -d "$CONTROLLER" "${NODES[@]}"
}

command_stop() {
  "${COMPOSE[@]}" stop "$CONTROLLER" "${NODES[@]}"
}

command_status() {
  "${COMPOSE[@]}" ps "$CONTROLLER" "${NODES[@]}"
}

command_shell() {
  local target="$CONTROLLER"
  if [[ $# -gt 0 ]]; then
    ensure_service "$1"
    target="$1"
    shift
  fi
  ensure_running "$target"
  if [[ $# -eq 0 ]]; then
    "${COMPOSE[@]}" exec -it "$target" bash
  else
    "${COMPOSE[@]}" exec -it "$target" "$@"
  fi
}

command_reconcile() {
  wait_for_controller
  if [[ $# -gt 0 ]]; then
    ensure_node "$1"
    ensure_running "$1"
    "${COMPOSE[@]}" exec "$1" landscape-agent --once
  else
    for node in "${NODES[@]}"; do
      ensure_running "$node"
      "${COMPOSE[@]}" exec "$node" landscape-agent --once
    done
  fi
}

command_topology() {
  require_args 2 "$@"
  local node="$1"
  local group="$2"
  ensure_node "$node"
  python3 - "$STATE_FILE" "$node" "$group" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
node = sys.argv[2]
group = sys.argv[3]

with state_path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)

data.setdefault("topology", {})[node] = group

with state_path.open("w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
  echo "Updated topology: $node -> $group"
}

command_broadcast() {
  if [[ $# -eq 0 ]]; then
    cat "$BROADCAST_SOURCE"
    return
  fi
  local source="$1"
  if [[ "$source" == "-" ]]; then
    cat >"$BROADCAST_SOURCE"
  else
    if [[ ! -f "$source" ]]; then
      echo "Broadcast source file not found: $source" >&2
      exit 1
    fi
    cp "$source" "$BROADCAST_SOURCE"
  fi
  chmod 0644 "$BROADCAST_SOURCE"
  echo "Replaced broadcast seed at $BROADCAST_SOURCE"
}

command_state() {
  wait_for_controller
  local targets=()
  if [[ $# -gt 0 ]]; then
    ensure_node "$1"
    ensure_running "$1"
    targets=($1)
  else
    targets=("${NODES[@]}")
  fi
  for node in "${targets[@]}"; do
    echo "=== $node ==="
    "${COMPOSE[@]}" exec "$CONTROLLER" curl -fsS "http://localhost:8028/state/$node" | python3 -m json.tool
  done
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  start) command_start "$@" ;;
  stop) command_stop "$@" ;;
  status) command_status "$@" ;;
  shell) command_shell "$@" ;;
  reconcile) command_reconcile "$@" ;;
  topology) command_topology "$@" ;;
  broadcast) command_broadcast "$@" ;;
  state) command_state "$@" ;;
  *)
    usage
    exit 1
    ;;
esac
