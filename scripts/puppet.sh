#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
AGENTS=(puppet-agent-panelpc puppet-agent-qg-1 puppet-agent-qg-2)

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start            Start the Puppet server and agent containers
  stop             Stop the Puppet containers
  status           Show the Puppet containers status
  logs [ARGS]      Stream Puppet agent logs (default: -f ${AGENTS[*]})
  test [AGENT]     Run 'puppet agent --test' inside the chosen agent (default: ${AGENTS[0]})
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
    "${COMPOSE[@]}" up -d puppetserver "${AGENTS[@]}"
    ;;
  stop)
    "${COMPOSE[@]}" stop puppetserver "${AGENTS[@]}"
    ;;
  status)
    "${COMPOSE[@]}" ps puppetserver "${AGENTS[@]}"
    ;;
  logs)
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" logs -f "${AGENTS[@]}"
    else
      "${COMPOSE[@]}" logs "$@"
    fi
    ;;
  test)
    target="${AGENTS[0]}"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi
    "${COMPOSE[@]}" exec "$target" puppet agent --test "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
