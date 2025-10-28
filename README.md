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

- `scripts/saltstack.sh`: start/stop the master and all minions, run states, or open a shell on the master.
- `scripts/puppet.sh`: manage the server and both agents, follow logs, or trigger `puppet agent --test` on either node.
- `scripts/ansible.sh`: start/stop the three pull nodes, open shells, run playbooks, or execute `ansible-pull` runs.
- `scripts/chef.sh`: start/stop the three local-mode clients, open shells, or run converges.
- `scripts/landscape.sh`: orchestrate the Landscape demo controller, trigger reconciles, adjust topology, and manage the broadcast seed file.

Each script prints usage details when invoked without arguments.

Download the required images once before you start experimenting:

```bash
docker compose pull
```

## SaltStack

- Configuration lives under `saltstack/`. Each minion mounts its own config directory (see `saltstack/minion-panelpc.d`, `saltstack/minion-qg-1.d`, and `saltstack/minion-qg-2.d`).
- Start the master and all minions:

  ```bash
  docker compose up -d salt-master salt-minion-panelpc salt-minion-qg-1 salt-minion-qg-2
  ```

- Auto-accept is enabled, but you can still verify keys:

  ```bash
  docker compose exec salt-master salt-key --list-all
  ```

- Apply the sample state to ensure `curl` is installed everywhere:

  ```bash
  scripts/saltstack.sh state
  ```

  The `demo` state simply invokes `pkg.installed` for `curl`, so every minion converges to the same baseline package set.

## Puppet

- Manifests live under `puppet/code/environments/production/`. The sample `site.pp` simply ensures the `curl` package is present on every agent.
- Start the server and the three agents (each based on the Jammy Ubuntu Puppet agent image):

  ```bash
  docker compose up -d puppetserver puppet-agent-panelpc puppet-agent-qg-1 puppet-agent-qg-2
  ```

- The server autosigns agent certificates (`puppet/autosign.conf`). Agents loop every 60 seconds, so you can follow their logs:

  ```bash
  docker compose logs -f puppet-agent-panelpc puppet-agent-qg-1 puppet-agent-qg-2
  ```

- Use the helper to trigger a test run on any node when you want an immediate converge:

  ```bash
  scripts/puppet.sh test puppet-agent-panelpc
  ```

  > **Tip:** If you previously ran the old agent containers, clear the cached SSL state (`rm -rf puppet/agent-*/ssl/*`) so the new certnames (`panelpc`, `qg-1`, `qg-2`) can register cleanly with the server.

## Ansible Pull + Push

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

## Chef Infra

- Cookbooks live in `chef/cookbooks/`. The `demo` run list now reconciles shared state using `/workspace/topology.yml`: it installs the common package baseline, manages the PanelPC broadcast file for worker nodes, and applies QG/DV specific packages while refreshing an informative MOTD.
- Start the three clients:

  ```bash
  docker compose up -d chef-panelpc chef-qg-1 chef-qg-2
  ```

- Converge each client in local mode:

  ```bash
  docker compose exec chef-panelpc chef-client -z -c /workspace/client.rb -o demo
  docker compose exec chef-qg-1 chef-client -z -c /workspace/client.rb -o demo
  docker compose exec chef-qg-2 chef-client -z -c /workspace/client.rb -o demo
  ```

- Adjust node membership or add new tiers by editing `chef/topology.yml` on the host (mounted at `/workspace/topology.yml` in the containers) and re-running the converge command.

  > **Tip:** If you already had the containers running before switching to the Chef Workstation image, recreate them (`docker compose up -d --force-recreate chef-panelpc chef-qg-1 chef-qg-2`) so the updated tooling is available.

## Canonical Landscape Demo

- A lightweight controller (`landscape-controller`) serves desired state and collects exports from three agents (`landscape-panelpc`, `landscape-qg-1`, `landscape-qg-2`).
- Start or stop the fleet with the helper:

  ```bash
  scripts/landscape.sh start   # or stop/status
  ```

- Trigger immediate reconciles or inspect rendered policy without waiting for the 30-second loop:

  ```bash
  scripts/landscape.sh reconcile         # run once on every node
  scripts/landscape.sh state landscape-qg-1
  ```

- The helper auto-starts any missing containers, so you can invoke `reconcile`, `state`, or `shell` directly and it will launch dependencies as needed.

- PanelPC owns the broadcast file (`/workspace/data/broadcast.txt`). Replace the seed content and have Landscape push it to workers:

  ```bash
  scripts/landscape.sh broadcast ./landscape/state/broadcasts/panelpc-note.txt
  scripts/landscape.sh reconcile
  docker compose exec landscape-qg-1 cat /opt/landscape/broadcast.txt
  ```

- Swap a node between tiers without touching container builds—Landscape recalculates packages and files on the fly:

  ```bash
  scripts/landscape.sh topology landscape-qg-2 worker
  scripts/landscape.sh reconcile landscape-qg-2
  docker compose exec landscape-qg-2 dpkg -l jq | grep ^ii
  ```

- Each agent refreshes apt caches on demand (`apt_update: true`) and enforces tier-specific MOTD fragments under `/etc/landscape-demo/motd.d/` so you can see the group identity from inside the container.

## Cleanup

Stop the environment when you are finished:

```bash
docker compose down
```

Persistent data such as Puppet certificates live inside `puppet/agent/ssl` and `puppet/agent-2/ssl`, while the other demos are stateless so you can destroy and recreate containers without losing work.

## Evaluation

| Tool | Reconcile Nodes | Distribute File | QG/DV State | PPC/Worker State | Change Topology |
|------|------------------|-----------------|--------------|------------------|-----------------|
| Salt Stack | ☐ | ☐ | ☐ | ☐ | ☐ |
| Puppet | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chef | ✅ | ✅ | ✅ | ✅ | ✅ |
| Ansible (Push + Pull) | ⚙️ | ✅ | ✅ | ✅ | 🚧 |
| Canonical Landscape | ✅ | ✅ | ✅ | ✅ | ✅ |
| Salt Reactor + Beacons | ☐ | ☐ | ☐ | ☐ | ☐ |
| Salt SSH (Standalone) | ☐ | ☐ | ☐ | ☐ | ☐ |
| CFEngine | ☐ | ☐ | ☐ | ☐ | ☐ |

### Chef
* ✅ Reconcile Nodes: `chef-client` converges every run-list item, ensuring packages, files, and MOTD stay in the declared state.
* ✅ Distribute File: PanelPC maintains `shared/panelpc/broadcast.txt` and worker nodes mirror it to `/opt/panelpc/broadcast.txt`.
* ✅ QG/DV State: Group-specific package arrays deliver QG utilities (`tmux`) and DV toolchains (`build-essential`).
* ✅ PPC/Worker State: PanelPC pulls in orchestration tooling (`git`) while workers gain their runtime helpers (`jq`).
* ✅ Change Topology: Adjust `chef/topology.yml` and rerun the converge to reassign nodes without altering code.

### Canonical Landscape
* ✅ Reconcile Nodes: Agents poll the controller every 30 seconds (or on demand with `reconcile`) and enforce packages plus managed files.
* ✅ Distribute File: PanelPC exports its broadcast file and the controller templates it onto every worker at `/opt/landscape/broadcast.txt`.
* ✅ QG/DV State: Group inheritance layers QG utilities (`tmux`) and DV build tooling (`build-essential`) on top of the worker baseline.
* ✅ PPC/Worker State: PanelPC receives control-plane tools (`git`) and owns the broadcast seed while workers inherit lighter runtime helpers (`jq`).
* ✅ Change Topology: `scripts/landscape.sh topology <node> <group>` edits the desired state live—agents adopt new tiers on their next poll.

### Ansible
* ⚙️ Reconcile Nodes: Idempotent, but no persistent agent to continuously enforce state. Use cron or AWX for periodic enforcement.

* ✅ Distribute File: Built-in modules (copy, template, fetch) make this straightforward.

* ✅ QG/DV State: Different playbooks or inventory groups handle environment-specific configs.

* ✅ PPC/Worker State: Host group variables and roles fit this model perfectly.

* 🚧 Change Topology: Requires manual edits to inventory or dynamic scripts; no auto-reconfiguration.

### Puppet
* ✅ Reconcile Nodes: `class demo` enforces packages, files, and MOTD across every agent via the new module under `puppet/code/environments/production/modules/demo`.

* ✅ Distribute File: PanelPC renders `/opt/puppetdemo/panelpc/broadcast.txt`, and worker agents sync the same content to `/opt/puppetdemo/broadcasts/broadcast.txt`.

* ✅ QG/DV State: Role-aware package lists from Hiera add QG utilities (`tmux`) and DV toolchains (`build-essential`) only where needed.

* ✅ PPC/Worker State: PanelPC picks up orchestration tools (`git`) while workers inherit helpers (`jq`) alongside the common baseline.

* ✅ Change Topology: Adjust host membership in `puppet/code/environments/production/data/common.yaml` (or add per-node YAML files) and rerun `scripts/puppet.sh test <agent>` to reconverge with the new mapping.
