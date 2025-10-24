#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start            Start the Puppet server and agent containers
  stop             Stop the Puppet containers
  status           Show the Puppet containers status
  logs [ARGS]      Stream Puppet agent logs (default: -f puppet-agent)
  test [ARGS]      Run 'puppet agent --test' inside the agent container
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
    "${COMPOSE[@]}" up -d puppetserver puppet-agent
    ;;
  stop)
    "${COMPOSE[@]}" stop puppetserver puppet-agent
    ;;
  status)
    "${COMPOSE[@]}" ps puppetserver puppet-agent
    ;;
  logs)
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" logs -f puppet-agent
    else
      "${COMPOSE[@]}" logs "$@"
    fi
    ;;
  test)
    "${COMPOSE[@]}" exec puppet-agent puppet agent --test "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
