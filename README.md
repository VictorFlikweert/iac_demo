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

### Beacon + Reactor Auto-Reconcile Demo

The master ships with a presence beacon (`saltstack/master.d/beacons.conf`) and a matching reactor (`saltstack/master.d/reactor.conf`) that watches for minions that reconnect after downtime. When the beacon reports new arrivals, the reactor SLS at `saltstack/states/reactor/presence/reconcile.sls` launches a `state.highstate` against just those minions, bringing them back in sync automatically.

Try it out:

1. Start the Salt stack if it is not already running:
   ```bash
   docker compose up -d salt-master salt-minion-panelpc salt-minion-qg-1 salt-minion-qg-2
   ```
2. Follow the master log so you can see the beacon and reactor chatter:
   ```bash
   docker compose logs -f salt-master
   ```
3. Simulate an outage for one minion and bring it back:
   ```bash
   docker compose stop salt-minion-qg-1
   sleep 10
   docker compose start salt-minion-qg-1
   ```
4. Watch the master log: once the minion reconnects you should see a `presence` event, followed by a job that runs `state.highstate` on the returning node. Any drift (for example removing `curl` while it was offline) is corrected automatically.

Need a different reconciliation? Adjust the target list in `beacons.conf` or swap out the state that runs inside `presence/reconcile.sls`.

Prefer a one-liner? The helper script wraps the whole flow (logs + stop/start) for you:

```bash
scripts/saltstack.sh presence-demo [salt-minion-name]
```

It tails the master logs *and* the Salt event bus, restarts the chosen minion (default `salt-minion-qg-1`), and leaves everything online long enough to catch either the presence beacon (`salt/beacon/<minion>/presence/present`) or the built-in minion start events (`salt/minion/<minion>/start`) and the resulting auto highstate job. Tweak the dwell times with `PRESENCE_DEMO_DOWN=<seconds>` and `PRESENCE_DEMO_SETTLE=<seconds>` if you need a longer outage or observation window.

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

- Cookbooks are under `chef/cookbooks/`. The bundled `demo` run list simply ensures `curl` is present on each client.
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

  > **Tip:** If you already had the containers running before switching to the Chef Workstation image, recreate them (`docker compose up -d --force-recreate chef-panelpc chef-qg-1 chef-qg-2`) so the updated tooling is available.

## Cleanup

Stop the environment when you are finished:

```bash
docker compose down
```

Persistent data such as Puppet certificates live inside `puppet/agent/ssl` and `puppet/agent-2/ssl`, while the other demos are stateless so you can destroy and recreate containers without losing work.



| Task | Salt Stack | Puppet | Ansible | Chef | Ansible (with AWX) | Ansible (Push + Local Cache) | Ansible Pull | Canonical Landscape | Salt Reactor + Beacons | Salt SSH (Standalone) | Rudder | CFEngine |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Reconciliation of node states | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Creating a file on PanelPC and distribute it to worker nodes | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Specific state for QG and DV nodes | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Specific state for PPC and worker nodes | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Ability to change node topology after deployment | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
