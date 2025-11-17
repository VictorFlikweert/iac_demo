#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="$REPO_ROOT/ansible/ssh/id_rsa"
DEFAULT_INVENTORY="/workspace/inventory.ini"
DEFAULT_PLAYBOOK="/workspace/playbooks/update.yml"
ANSIBLE_NODES=(ansible-panelpc ansible-worker-qg-1 ansible-worker-qg-2)
DEFAULT_NODE="${ANSIBLE_NODES[0]}"

is_node() {
  local candidate="$1"
  for node in "${ANSIBLE_NODES[@]}"; do
    if [[ "$node" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

ensure_ssh_perms() {
  if [[ -f "$SSH_KEY" ]]; then
    chmod 600 "$SSH_KEY"
  fi
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
  pull [NODE] [ENV=VAL...]      Run the post-pull workflow script inside the chosen node
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
    ensure_ssh_perms
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
    ensure_ssh_perms
    target="$DEFAULT_NODE"
    if [[ $# -gt 0 ]] && is_node "$1"; then
      target="$1"
      shift
    fi
    playbook="${1:-$DEFAULT_PLAYBOOK}"
    if [[ $# -gt 0 ]]; then
      shift
    fi
    args=(ansible-playbook -i "$DEFAULT_INVENTORY" "$playbook")
    "${COMPOSE[@]}" exec "$target" "${args[@]}" "$@"
    ;;
  pull)
    ensure_ssh_perms
    target="$DEFAULT_NODE"
    if [[ $# -gt 0 ]] && is_node "$1"; then
      target="$1"
      shift
    fi
    env_flags=()
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == *=* ]]; then
        env_flags+=(-e "$1")
        shift
      else
        break
      fi
    done
    "${COMPOSE[@]}" exec "${env_flags[@]}" "$target" /workspace/scripts/post_pull.sh "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
