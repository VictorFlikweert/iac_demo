#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-$WORKSPACE/ansible.cfg}"

INVENTORY="${INVENTORY:-$WORKSPACE/inventory.ini}"
UPDATE_PLAYBOOK="${UPDATE_PLAYBOOK:-$WORKSPACE/playbooks/update.yml}"
AUDIT_PLAYBOOK="${AUDIT_PLAYBOOK:-$WORKSPACE/playbooks/audit.yml}"
TRANSFER_FILE_PLAYBOOK="${TRANSFER_FILE_PLAYBOOK:-$WORKSPACE/playbooks/transfer_file.yml}"

echo "[post-pull] Running update playbook: $UPDATE_PLAYBOOK"
ansible-playbook -i "$INVENTORY" "$UPDATE_PLAYBOOK"

echo "[post-pull] Running transfer_file playbook: $TRANSFER_FILE_PLAYBOOK"
ansible-playbook -i "$INVENTORY" "$TRANSFER_FILE_PLAYBOOK"

if [[ "${RUN_AUDIT:-0}" == "1" ]]; then
  echo "[post-pull] Running audit playbook: $AUDIT_PLAYBOOK"
  ansible-playbook -i "$INVENTORY" "$AUDIT_PLAYBOOK"
fi
