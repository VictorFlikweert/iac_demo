# IaC Tooling Playground

This repository provides a Docker Compose driven lab for exploring multiple infrastructure-as-code (IaC) tools side-by-side:

- SaltStack (master with three minions: `minion-panelpc`, `minion-qg-1`, `minion-qg-2`)
- Puppet (server with three agents installing `curl`)
- Ansible using `ansible-pull` on three containers (`ansible-panelpc`, `ansible-qg-1`, `ansible-qg-2`)
- Chef Infra Client (three local-mode clients matching the Ansible nodes)

The compose file keeps configurations on the host so you can iterate quickly on states/manifests/playbooks/cookbooks without rebuilding containers.

## Prerequisites

- Docker Engine 20.x or newer
- Docker Compose Plugin (or `docker-compose` binary)

## Utility Scripts

Wrapper scripts in `scripts/` streamline common workflows:

- `scripts/saltstack.sh`: start/stop the master and all minions, run targeted states or highstate, sync modules, inspect pillar data, or open a shell on the master.
- `scripts/puppet.sh`: manage the server and both agents, follow logs, or trigger `puppet agent --test` on either node.
- `scripts/ansible.sh`: start/stop the three pull nodes, open shells, run playbooks, or execute `ansible-pull` runs.
- `scripts/chef.sh`: start/stop the three local-mode clients, open shells, or run converges.

Each script prints usage details when invoked without arguments.

Download the required images once before you start experimenting:

```bash
docker compose pull
```

## SaltStack

- Configuration lives under `saltstack/`: `states/demo` contains the topology-aware state, while `pillar/demo.sls` holds the editable data model (roles, packages, broadcast message, topology defaults).
- Launch the environment with the helper:

  ```bash
  scripts/saltstack.sh start   # stop/status available too
  ```

  Auto-accept remains enabled, so new minions register immediately; use `scripts/saltstack.sh shell salt-key --list-all` if you still want to inspect keys.

- Apply the Salt demo to every minion (defaults: target `minion-*`, state `demo`):

  ```bash
  scripts/saltstack.sh state
  ```

  Swap in specific targets or pass extra Salt arguments (`scripts/saltstack.sh state 'minion-qg-*' demo test=True`) and lean on `highstate`, `sync`, and `pillar` subcommands when iterating:

  ```bash
  scripts/saltstack.sh highstate           # reconcile the full top file
  scripts/saltstack.sh sync                # saltutil.sync_all after edits
  scripts/saltstack.sh pillar minion-qg-1  # inspect merged pillar data
  ```

- The `demo` state enforces shared packages (`curl`, `vim-tiny`), role packages (panelpc `git`, workers `jq`, QG `tmux`, DV `build-essential`), manages `/opt/saltdemo/panelpc/broadcast.txt`, distributes the same message to workers at `/opt/saltdemo/broadcasts/broadcast.txt`, and refreshes `/etc/motd` with current roles and topology context.
- Adjust group membership or package mixes by editing `saltstack/pillar/demo.sls` on the host, syncing, and re-running `scripts/saltstack.sh highstate`. Add minion IDs to the pillar host lists to cover new targets without touching state code.

## Ansible Pull

- The control node (`ansible-panelpc`) now pulls configuration and then pushes it to worker nodes over SSH.
- Start or stop the fleet with the helper:

  ```bash
  scripts/ansible.sh start   # or stop/status
  ```

  This brings up `ansible-panelpc` (built via `ansible/panelpc.Dockerfile` to include the SSH client) plus two SSH-enabled workers (`ansible-worker-qg-1`, `ansible-worker-qg-2`) built from `ansible/worker.Dockerfile`.

- Kick off the workflow from the host. By default it refreshes packages via `playbooks/update.yml` and then distributes the transfer file with `playbooks/transfer_file.yml`:

  ```bash
  scripts/ansible.sh pull
  ```

- Add environment overrides to tweak the run, for example to enable the audit playbook:

  ```bash
  scripts/ansible.sh pull RUN_AUDIT=1
  ```

  Inside the container this executes `/workspace/scripts/post_pull.sh`, which in turn runs `ansible-playbook` for `update.yml` and `transfer_file.yml` (plus `audit.yml` when `RUN_AUDIT=1`).

- You can run additional playbooks directly against the workers from panelpc:

  ```bash
  scripts/ansible.sh playbook ansible-panelpc /workspace/playbooks/audit.yml
  ```

  > **Note:** The SSH key under `ansible/ssh` is bundled purely for the lab. Replace it (and rebuild the worker images) before reusing the pattern elsewhere.

### Task: Distribute a file from panelpc to the workers

1. Make sure the Ansible containers are running:

   ```bash
   scripts/ansible.sh start
   ```

2. Run the bundled workflow. The first play ensures `/workspace/transfers/panelpc-note.txt` exists on panelpc, and the second play copies it to `/tmp/panelpc-note.txt` on every worker:

   ```bash
   scripts/ansible.sh pull
   ```

3. Verify the file landed on the workers:

   ```bash
   scripts/ansible.sh shell ansible-panelpc ansible workers -i /workspace/inventory.ini -a "cat /tmp/panelpc-note.txt"
   ```

   > **Customize it:** Edit `ansible/playbooks/transfer_file.yml` to change the payload content, destinations, or ownership, and adjust `ansible/playbooks/update.yml` for any package state tweaks.

## Cleanup

Stop the environment when you are finished:

```bash
docker compose down
```

Persistent data such as Puppet certificates live inside `puppet/agent/ssl` and `puppet/agent-2/ssl`, while the other demos are stateless so you can destroy and recreate containers without losing work.
