#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
DEFAULT_INVENTORY="/workspace/inventory.ini"
DEFAULT_PLAYBOOK="/workspace/playbooks/local.yml"
DEFAULT_PULL_REPO="file:///workspace/pull_repo"

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start                     Start the Ansible ansible-pull container
  stop                      Stop the Ansible container
  status                    Show the Ansible container status
  shell [CMD]               Open a shell (default: bash) in the ansible-pull container
  playbook [PLAYBOOK] [...] Run ansible-playbook (default playbook: $DEFAULT_PLAYBOOK)
  pull [REPO] [ARGS...]     Run ansible-pull (default repo: $DEFAULT_PULL_REPO)
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
    "${COMPOSE[@]}" up -d ansible-pull
    ;;
  stop)
    "${COMPOSE[@]}" stop ansible-pull
    ;;
  status)
    "${COMPOSE[@]}" ps ansible-pull
    ;;
  shell)
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" exec -it ansible-pull bash
    else
      "${COMPOSE[@]}" exec -it ansible-pull "$@"
    fi
    ;;
  playbook)
    playbook="${1:-$DEFAULT_PLAYBOOK}"
    if [[ $# -gt 0 ]]; then
      shift
    fi
    "${COMPOSE[@]}" exec ansible-pull ansible-playbook -i "$DEFAULT_INVENTORY" "$playbook" "$@"
    ;;
  pull)
    repo="${1:-$DEFAULT_PULL_REPO}"
    if [[ $# -gt 0 ]]; then
      shift
    fi
    "${COMPOSE[@]}" exec ansible-pull ansible-pull -U "$repo" -d /tmp/ansible-pull -i "$DEFAULT_INVENTORY" "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
