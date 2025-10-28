#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
NODES=(cfengine-panelpc cfengine-qg-1 cfengine-qg-2)
RENDER_SCRIPT="cfengine/render_topology.py"
POLICY_PATH="/workspace/promises.cf"

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start                 Render topology and start all CFEngine containers
  stop                  Stop the CFEngine containers
  status                Show container status
  render                Rebuild services/generated_topology.cf from topology.json
  converge [TARGET...]  Run cf-agent -KI using promises.cf (defaults to all nodes)
  shell [TARGET] [CMD]  Open a shell (default bash) in TARGET container
EOF
}

render_topology() {
  local candidates=()
  if [[ -n "${PYTHON3:-}" ]]; then
    candidates+=("$PYTHON3")
  fi
  if [[ -n "${PYTHON:-}" ]]; then
    candidates+=("$PYTHON")
  fi
  candidates+=(python3 python)

  local chosen=""
  for bin in "${candidates[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
      chosen="$bin"
      break
    fi
  done

  if [[ -n "$chosen" ]]; then
    "$chosen" "$RENDER_SCRIPT"
  else
    echo "python3 not found on host; skipping regeneration of generated_topology.cf." >&2
    echo "Install python3 (or set PYTHON3/PYTHON) to rebuild cfengine/services/generated_topology.cf from topology.json." >&2
  fi
}

ensure_known_node() {
  local node="$1"
  for candidate in "${NODES[@]}"; do
    if [[ "$candidate" == "$node" ]]; then
      return 0
    fi
  done
  echo "Unknown node: $node" >&2
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  start)
    render_topology
    "${COMPOSE[@]}" up -d "${NODES[@]}"
    ;;
  stop)
    "${COMPOSE[@]}" stop "${NODES[@]}"
    ;;
  status)
    "${COMPOSE[@]}" ps "${NODES[@]}"
    ;;
  render)
    render_topology
    ;;
  converge)
    render_topology
    if [[ $# -eq 0 ]]; then
      set -- "${NODES[@]}"
    fi
    for node in "$@"; do
      ensure_known_node "$node"
      "${COMPOSE[@]}" up -d "$node"
      "${COMPOSE[@]}" exec -T "$node" cf-agent -KI -f "$POLICY_PATH"
    done
    ;;
  shell)
    if [[ $# -eq 0 ]]; then
      set -- cfengine-panelpc
    fi
    target="$1"
    ensure_known_node "$target"
    shift || true
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" exec -it "$target" bash
    else
      "${COMPOSE[@]}" exec -it "$target" "$@"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
