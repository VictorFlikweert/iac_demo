#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
MINIONS=(salt-minion-panelpc salt-minion-qg-1 salt-minion-qg-2)
ALL_CONTAINERS=(salt-master "${MINIONS[@]}")

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start                 Start the Salt master and all minion containers
  stop                  Stop the Salt containers
  status                Show the Salt containers status
  state [TARGET] [STATE] [ARGS]
                        Run salt <target> state.apply <state> (defaults: target='minion-*', state='demo')
  highstate [TARGET]    Run salt <target> state.highstate (default target='minion-*')
  sync [TARGET]         Run salt <target> saltutil.sync_all to refresh modules/files (default target='minion-*')
  pillar [TARGET] [KEY] Show pillar data (defaults: target='minion-*', command=pillar.items)
  shell [CMD]           Open a shell (default: bash) in the salt-master container
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
    "${COMPOSE[@]}" up -d "${ALL_CONTAINERS[@]}"
    ;;
  stop)
    "${COMPOSE[@]}" stop "${ALL_CONTAINERS[@]}"
    ;;
  status)
    "${COMPOSE[@]}" ps "${ALL_CONTAINERS[@]}"
    ;;
  state)
    target="minion-*"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi
    state_name="demo"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      state_name="$1"
      shift
    fi
    "${COMPOSE[@]}" exec salt-master salt "$target" state.apply "$state_name" "$@"
    ;;
  highstate)
    target="minion-*"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi
    "${COMPOSE[@]}" exec salt-master salt "$target" state.highstate "$@"
    ;;
  sync)
    target="minion-*"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi
    "${COMPOSE[@]}" exec salt-master salt "$target" saltutil.sync_all "$@"
    ;;
  pillar)
    target="minion-*"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi
    if [[ $# -gt 0 ]]; then
      key="$1"
      shift
      "${COMPOSE[@]}" exec salt-master salt "$target" pillar.item "$key" "$@"
    else
      "${COMPOSE[@]}" exec salt-master salt "$target" pillar.items "$@"
    fi
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
