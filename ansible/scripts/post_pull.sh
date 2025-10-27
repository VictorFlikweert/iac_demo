#!/usr/bin/env bash
set -euo pipefail
REPO_DIR=/srv/infra/ansible
cd "$REPO_DIR"

INV=/etc/ansible/hosts

# 3a) Quick inventory view
ansible -i "$INV" all --list-hosts

# 3b) Gather full facts (hardware/OS/network/packages/services)
#     Cache them for reporting (see §4 below).
ansible -i "$INV" all -m setup --tree .facts/

# 3c) Extra facts: packages and services (more concrete view)
ansible -i "$INV" all -m package_facts --args 'manager=auto'
ansible -i "$INV" all -m service_facts

# 3d) Drift preview: what WOULD change if we ran site.yml?
#     (No changes applied; useful to see real differences.)
ansible-playbook -i "$INV" playbooks/site.yml --check --diff \
  | tee logs/last_check_run.log

# 3e) Optional: targeted ad-hoc checks
# Example: show nginx version on web hosts
ansible -i "$INV" web -m command -a "nginx -v" -o || true

# Example: pull specific config files to inspect centrally
# (collects files into ./collected/<host>/*)
ansible -i "$INV" all -m fetch \
  -a "src=/etc/ssh/sshd_config dest=collected/{{ inventory_hostname }}/ flat=yes" || true
