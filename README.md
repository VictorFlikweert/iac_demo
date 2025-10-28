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

## Ansible Pull

- Author playbooks under `ansible/`. Each container runs playbooks locally using the shared inventory (`panelpc`, `qg-1`, and `qg-2`).
- Start the three nodes:

  ```bash
  docker compose up -d ansible-panelpc ansible-qg-1 ansible-qg-2
  ```

- Run the sample playbook on any node to ensure `curl` is installed:

  ```bash
  docker compose exec ansible-panelpc ansible-playbook -i /workspace/inventory.ini /workspace/playbooks/local.yml --limit panelpc
  docker compose exec ansible-qg-1 ansible-playbook -i /workspace/inventory.ini /workspace/playbooks/local.yml --limit qg-1
  docker compose exec ansible-qg-2 ansible-playbook -i /workspace/inventory.ini /workspace/playbooks/local.yml --limit qg-2
  ```

- To try a true `ansible-pull` workflow using the sample repo:

  1. Turn `ansible/pull_repo` into a Git repository on the host:

     ```bash
     cd ansible/pull_repo
     git init
     git add site.yml
     git commit -m "Initial demo playbook"
     ```

  2. Run `ansible-pull` from inside any node container, pointing at the mounted repository:

     ```bash
     ansible-pull -U file:///workspace/pull_repo -d /tmp/ansible-pull -i /workspace/inventory.ini
     ```

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

## Cleanup

Stop the environment when you are finished:

```bash
docker compose down
```

Persistent data such as Puppet certificates live inside `puppet/agent/ssl` and `puppet/agent-2/ssl`, while the other demos are stateless so you can destroy and recreate containers without losing work.

## Evaluation

| Task | Salt Stack | Puppet | Ansible | Chef | Ansible (with AWX) | Ansible (Push + Local Cache) | Ansible Pull | Canonical Landscape | Salt Reactor + Beacons | Salt SSH (Standalone) | Rudder | CFEngine |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Reconciliation of node states | [ ] | [ ] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Creating a file on PanelPC and distribute it to worker nodes | [ ] | [ ] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Specific state for QG and DV nodes | [ ] | [ ] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Specific state for PPC and worker nodes | [ ] | [ ] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Ability to change node topology after deployment | [ ] | [ ] | [ ] | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
