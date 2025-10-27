#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
DEFAULT_INVENTORY="/tmp/ansible-pull/ansible/inventory.ini"
DEFAULT_PLAYBOOK="/tmp/ansible-pull/ansible/playbooks/local.yml"
DEFAULT_PULL_REPO="https://github.com/VictorFlikweert/iac_demo"
ANSIBLE_NODES=(ansible-panelpc ansible-qg-1 ansible-qg-2)
DEFAULT_NODE="${ANSIBLE_NODES[0]}"
declare -A NODE_INVENTORY=(
  [ansible-panelpc]="panelpc"
  [ansible-qg-1]="qg-1"
  [ansible-qg-2]="qg-2"
)

is_node() {
  local candidate="$1"
  for node in "${ANSIBLE_NODES[@]}"; do
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
  start                         Start the Ansible node containers
  stop                          Stop the Ansible containers
  status                        Show the Ansible container status
  shell [NODE] [CMD]            Open a shell (default: bash) in the chosen node (default: $DEFAULT_NODE)
  playbook [NODE] [PLAYBOOK]    Run ansible-playbook inside the chosen node (auto-limited to its inventory host)
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
    "${COMPOSE[@]}" up -d "${ANSIBLE_NODES[@]}"
    ;;
  stop)
    "${COMPOSE[@]}" stop "${ANSIBLE_NODES[@]}"
    ;;
  status)
    "${COMPOSE[@]}" ps "${ANSIBLE_NODES[@]}"
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
  playbook)
    playbook="$DEFAULT_PLAYBOOK"

    # do NOT shift here; we want $1 to still be the possible node
    target="$DEFAULT_NODE"
    if [[ $# -gt 0 ]] && is_node "$1"; then
      target="$1"
      shift
    fi

    repo="${DEFAULT_PULL_REPO}"
    # do NOT shift here either; only shift if you actually parse an arg into 'repo'
    if [[ $# -gt 0 ]]; then
      repo="$1"
      shift
    fi

    # TODO: Before merging to main, remove '-C ansible-pull', so that it targets the main branch instead
    "${COMPOSE[@]}" exec "$target" ansible-pull -U "$repo" -C ansible-pull -d /tmp/ansible-pull "$playbook"
    ;;
  *)
    usage
    exit 1
    ;;
esac
