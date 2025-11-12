#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start          Start the Salt master and worker minion containers
  stop           Stop the Salt containers
  status         Show the Salt containers status
  state [TARGET] [ARGS]
                 Run salt <target> state.apply (default target: 'minion-*')
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
    "${COMPOSE[@]}" up -d salt-master salt-minion-qg-1 salt-minion-qg-2
    ;;
  stop)
    "${COMPOSE[@]}" stop salt-master salt-minion-qg-1 salt-minion-qg-2
    ;;
  status)
    "${COMPOSE[@]}" ps salt-master salt-minion-qg-1 salt-minion-qg-2
    ;;
  state)
    target="minion-*"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi
    "${COMPOSE[@]}" exec salt-master salt "$target" state.apply "$@"
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
