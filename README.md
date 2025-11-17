# IaC Tooling Playground

This repository provides a Docker Compose driven lab for exploring multiple infrastructure-as-code (IaC) tools side-by-side:

- SaltStack (master with three minions: `minion-panelpc`, `minion-qg-1`, `minion-qg-2`)
- Puppet (server with three agents installing `curl`)
- Ansible using `ansible-pull` on three containers (`ansible-panelpc`, `ansible-qg-1`, `ansible-qg-2`)
- Chef Infra Client (three local-mode clients matching the Ansible nodes)
- Observability stack (Prometheus + Grafana scraping to watch the lab containers, node_exporter inside the Ansible and Salt nodes, Salt state beacons pushing state metrics to Pushgateway, and an Ansible callback pushing run metrics to Pushgateway)

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

- Configuration lives under `saltstack/`: the `site` state pulls in `common` (package refresh/installs) and `transfer` (panelpc note distribution). The top file keys off grains (`roles: panelpc` on the master, `roles: worker` on the minions) to decide what to apply. Toggle the audit helper (`states/audit`) by setting a `run_audit: true` grain on a worker.
- Launch the environment with the helper:

  ```bash
  scripts/saltstack.sh start   # stop/status available too
  ```

  Auto-accept remains enabled, so new minions register immediately; use `scripts/saltstack.sh shell salt-key --list-all` if you still want to inspect keys.

- Apply the Salt site state to every minion (defaults: target `*`, state `site`):

  ```bash
  scripts/saltstack.sh state
  ```

  Swap in specific targets or pass extra Salt arguments (`scripts/saltstack.sh state 'minion-qg-*' site test=True`) and lean on `highstate`, `sync`, and `pillar` subcommands when iterating:

  ```bash
  scripts/saltstack.sh highstate           # reconcile the full top file
  scripts/saltstack.sh sync                # saltutil.sync_all after edits
  scripts/saltstack.sh pillar minion-qg-1  # inspect merged pillar/grain data
  ```

- The `common` state refreshes packages and installs `curl`/`vim-tiny`. `transfer` deploys a note from panelpc to workers, and `audit` gathers simple file/package facts when enabled via the `run_audit` grain.

## Ansible Pull

- The control node (`ansible-panelpc`) now pulls configuration and then pushes it to worker nodes over SSH.
- Start or stop the fleet with the helper:

  ```bash
  scripts/ansible.sh start   # or stop/status
  ```

  This brings up `ansible-panelpc` (built via `ansible-pull/panelpc.Dockerfile` to include the SSH client) plus two SSH-enabled workers (`ansible-worker-qg-1`, `ansible-worker-qg-2`) built from `ansible-pull/worker.Dockerfile`.

- Kick off the workflow from the host. By default it runs the master playbook `playbooks/site.yml`, which imports `update.yml`, then `transfer_file.yml`, and finally `audit.yml`:

  ```bash
  scripts/ansible.sh pull
  ```

- Add environment overrides to tweak the run, for example to enable the audit playbook:

  ```bash
  scripts/ansible.sh pull RUN_AUDIT=1
  ```

  Inside the container this executes `/workspace/scripts/post_pull.sh`, which in turn runs `ansible-pull` against the checked-out repo for `playbooks/site.yml` with `--limit all`. The `audit.yml` import is tagged `audit`, so it runs only when `RUN_AUDIT=1` (otherwise it is skipped).

- You can run additional playbooks directly against the workers from panelpc:

  ```bash
  scripts/ansible.sh playbook ansible-panelpc /workspace/playbooks/audit.yml
  ```

  > **Note:** The SSH key under `ansible-pull/ssh` is bundled purely for the lab. Replace it (and rebuild the worker images) before reusing the pattern elsewhere.

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

   > **Customize it:** Edit `ansible-pull/playbooks/transfer_file.yml` to change the payload content, destinations, or ownership, and adjust `ansible-pull/playbooks/update.yml` for any package state tweaks.

## Observability (Prometheus + Grafana)

- Services `prometheus`, `grafana`, and `pushgateway` are defined in `docker-compose.yml`. Prometheus scrapes itself and node_exporter on Ansible/Salt nodes (`:9100`), Pushgateway for Ansible run metrics and Salt state metrics (pushed by a custom beacon), and cAdvisor for container metrics if enabled.
- Start everything (including metrics) with:

  ```bash
  docker compose up -d
  ```

- Access Prometheus at http://localhost:9090 and Grafana at http://localhost:3000 (admin/admin by default). Grafana auto-provisions a Prometheus data source pointing at the in-compose Prometheus.

- Prometheus config lives at `prometheus/prometheus.yml`; Grafana datasource provisioning lives at `grafana/provisioning/datasources/prometheus.yml`. Targets include `node_exporter_iac` (Salt master/minions and Ansible nodes) and `pushgateway` (Ansible run metrics plus Salt state beacon metrics).
- Salt minions sync a custom beacon (`_beacons/state_metrics.py`) via the `beacons` state. The beacon watches `state.apply` return events and pushes success/change/failure counts and durations to the Pushgateway under the `salt_state` job. Ansible pulls use a custom callback in `/workspace/callback_plugins/prometheus_pushgateway.py` (enabled in `ansible.cfg`) to push playbook metrics to the Pushgateway (`PROM_PUSHGATEWAY_URL` overrideable).

## Cleanup

Stop the environment when you are finished:

```bash
docker compose down
```
