#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
DEFAULT_CONFIG="/workspace/client.rb"
DEFAULT_RUN_LIST="demo"

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start                     Start the Chef client container
  stop                      Stop the Chef container
  status                    Show the Chef container status
  shell [CMD]               Open a shell (default: bash) in the chef-client container
  converge [RUN_LIST] [...] Run chef-client -z using the given run list (default: $DEFAULT_RUN_LIST)
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
    "${COMPOSE[@]}" up -d chef-client
    ;;
  stop)
    "${COMPOSE[@]}" stop chef-client
    ;;
  status)
    "${COMPOSE[@]}" ps chef-client
    ;;
  shell)
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" exec -it chef-client bash
    else
      "${COMPOSE[@]}" exec -it chef-client "$@"
    fi
    ;;
  converge)
    run_list="${1:-$DEFAULT_RUN_LIST}"
    if [[ $# -gt 0 ]]; then
      shift
    fi
    "${COMPOSE[@]}" exec chef-client chef-client -z -c "$DEFAULT_CONFIG" -o "$run_list" "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
