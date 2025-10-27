#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-$WORKSPACE/ansible.cfg}"

INVENTORY="${INVENTORY:-$WORKSPACE/inventory.ini}"
UPDATE_PLAYBOOK="${UPDATE_PLAYBOOK:-$WORKSPACE/playbooks/update.yml}"
AUDIT_PLAYBOOK="${AUDIT_PLAYBOOK:-$WORKSPACE/playbooks/audit.yml}"

echo "[post-pull] Running update playbook: $UPDATE_PLAYBOOK"
ansible-playbook -i "$INVENTORY" "$UPDATE_PLAYBOOK"

if [[ "${RUN_AUDIT:-0}" == "1" ]]; then
  echo "[post-pull] Running audit playbook: $AUDIT_PLAYBOOK"
  ansible-playbook -i "$INVENTORY" "$AUDIT_PLAYBOOK"
fi
