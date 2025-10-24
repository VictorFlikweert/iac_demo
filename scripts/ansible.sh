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
  pull [NODE] [REPO] [ARGS...]  Run ansible-pull inside the chosen node
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
    target="$DEFAULT_NODE"
    if [[ $# -gt 0 ]] && is_node "$1"; then
      target="$1"
      shift
    fi
    playbook="${1:-$DEFAULT_PLAYBOOK}"
    if [[ $# -gt 0 ]]; then
      shift
    fi
    inventory_host="${NODE_INVENTORY[$target]:-}"
    args=(ansible-playbook -i "$DEFAULT_INVENTORY" "$playbook")
    if [[ -n "$inventory_host" ]]; then
      args+=(--limit "$inventory_host")
    fi
    "${COMPOSE[@]}" exec "$target" "${args[@]}" "$@"
    ;;
  pull)
    target="$DEFAULT_NODE"
    if [[ $# -gt 0 ]] && is_node "$1"; then
      target="$1"
      shift
    fi
    repo="${DEFAULT_PULL_REPO}"
    if [[ $# -gt 0 ]]; then
      shift
    fi
    "${COMPOSE[@]}" exec "$target" ansible-pull -U "$repo" -d /tmp/ansible-pull -i "$DEFAULT_INVENTORY" "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
