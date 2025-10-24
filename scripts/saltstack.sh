#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start          Start the Salt master and minion containers
  stop           Stop the Salt containers
  status         Show the Salt containers status
  state [ARGS]   Run salt '*' state.apply with optional extra arguments
  shell [CMD]    Open a shell (default: bash) in the salt-master container
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
    "${COMPOSE[@]}" up -d salt-master salt-minion
    ;;
  stop)
    "${COMPOSE[@]}" stop salt-master salt-minion
    ;;
  status)
    "${COMPOSE[@]}" ps salt-master salt-minion
    ;;
  state)
    "${COMPOSE[@]}" exec salt-master salt '*' state.apply "$@"
    ;;
  shell)
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" exec -it salt-master bash
    else
      "${COMPOSE[@]}" exec -it salt-master "$@"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
