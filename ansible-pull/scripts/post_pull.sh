#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-$WORKSPACE/ansible.cfg}"

INVENTORY="${INVENTORY:-$WORKSPACE/inventory.ini}"
PLAYBOOK="${PLAYBOOK:-$WORKSPACE/playbooks/site.yml}"

echo "[post-pull] Running update playbook: $PLAYBOOK"
ansible-playbook -i "$INVENTORY" "$PLAYBOOK"
