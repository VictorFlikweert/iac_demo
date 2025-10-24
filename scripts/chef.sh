#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
DEFAULT_CONFIG="/workspace/client.rb"
DEFAULT_RUN_LIST="demo"
CHEF_NODES=(chef-panelpc chef-qg-1 chef-qg-2)
DEFAULT_NODE="${CHEF_NODES[0]}"

is_node() {
  local candidate="$1"
  for node in "${CHEF_NODES[@]}"; do
    if [[ "$node" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start                          Start the Chef client containers
  stop                           Stop the Chef containers
  status                         Show the Chef containers status
  shell [NODE] [CMD]             Open a shell (default: bash) in the chosen client (default: $DEFAULT_NODE)
  converge [NODE] [RUN_LIST]     Run chef-client -z using the given run list (default: $DEFAULT_RUN_LIST)
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  start)
    "${COMPOSE[@]}" up -d "${CHEF_NODES[@]}"
    ;;
  stop)
    "${COMPOSE[@]}" stop "${CHEF_NODES[@]}"
    ;;
  status)
    "${COMPOSE[@]}" ps "${CHEF_NODES[@]}"
    ;;
  shell)
    target="$DEFAULT_NODE"
    if [[ $# -gt 0 ]] && is_node "$1"; then
      target="$1"
      shift
    fi
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" exec -it "$target" bash
    else
      "${COMPOSE[@]}" exec -it "$target" "$@"
    fi
    ;;
  converge)
    target="$DEFAULT_NODE"
    if [[ $# -gt 0 ]] && is_node "$1"; then
      target="$1"
      shift
    fi
    run_list="${1:-$DEFAULT_RUN_LIST}"
    if [[ $# -gt 0 ]]; then
      shift
    fi
    "${COMPOSE[@]}" exec "$target" chef-client -z -c "$DEFAULT_CONFIG" -o "$run_list" "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
