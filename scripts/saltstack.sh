#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start          Start the Salt master and all minion containers
  stop           Stop the Salt containers
  status         Show the Salt containers status
  state [TARGET] [ARGS]
                 Run salt <target> state.apply (default target: 'minion-*')
  shell [CMD]    Open a shell (default: bash) in the salt-master container
  presence-demo [MINION]
                 Tail master logs and event bus, restart the chosen minion (default: salt-minion-qg-1)
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
    "${COMPOSE[@]}" up -d salt-master salt-minion-panelpc salt-minion-qg-1 salt-minion-qg-2
    ;;
  stop)
    "${COMPOSE[@]}" stop salt-master salt-minion-panelpc salt-minion-qg-1 salt-minion-qg-2
    ;;
  status)
    "${COMPOSE[@]}" ps salt-master salt-minion-panelpc salt-minion-qg-1 salt-minion-qg-2
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
  presence-demo)
    target_minion="${1:-salt-minion-qg-1}"
    down_time="${PRESENCE_DEMO_DOWN:-20}"
    settle_time="${PRESENCE_DEMO_SETTLE:-30}"
    echo "Demo parameters: target=${target_minion}, down_time=${down_time}s, settle_time=${settle_time}s"
    echo "Ensuring Salt stack is running..."
    "${COMPOSE[@]}" up -d salt-master salt-minion-panelpc salt-minion-qg-1 salt-minion-qg-2

    echo "Restarting salt-master to pick up latest config..."
    "${COMPOSE[@]}" restart salt-master >/dev/null
    echo "Waiting for salt-master to settle..."
    sleep 5

    echo "Starting log follow on salt-master (will auto-stop at the end)..."
    "${COMPOSE[@]}" logs -f salt-master &
    log_pid=$!

    echo "Streaming Salt event bus (presence + reactor output)..."
    "${COMPOSE[@]}" exec -T salt-master sh -lc 'salt-run state.event pretty=True' &
    event_pid=$!

    cleanup() {
      if ps -p "$log_pid" >/dev/null 2>&1; then
        kill "$log_pid" >/dev/null 2>&1 || true
        wait "$log_pid" 2>/dev/null || true
      fi
      if [[ -n "${event_pid:-}" ]] && ps -p "$event_pid" >/dev/null 2>&1; then
        kill "$event_pid" >/dev/null 2>&1 || true
        wait "$event_pid" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

    sleep 3
    echo "Stopping $target_minion to simulate an outage..."
    "${COMPOSE[@]}" stop "$target_minion"

    echo "Keeping $target_minion offline for ${down_time}s to trigger presence detection..."
    sleep "$down_time"

    echo "Bringing $target_minion back online..."
    "${COMPOSE[@]}" start "$target_minion"

    echo "Allowing ${settle_time}s for beacon/reactor events and the auto highstate..."
    sleep "$settle_time"
    echo "Demo complete. Review the log and event output above for presence and state activity."
    cleanup
    trap - EXIT
    ;;
  *)
    usage
    exit 1
    ;;
esac
