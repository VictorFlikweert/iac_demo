# IaC Tooling Playground

This repository provides a Docker Compose driven lab for exploring multiple infrastructure-as-code (IaC) tools side-by-side:

- SaltStack (master and minion)
- Puppet (server and agent)
- Ansible using `ansible-pull`
- Chef Infra Client (local mode)

The compose file keeps configurations on the host so you can iterate quickly on states/manifests/playbooks/cookbooks without rebuilding containers.

## Prerequisites

- Docker Engine 20.x or newer
- Docker Compose Plugin (or `docker-compose` binary)

## Utility Scripts

Wrapper scripts in `scripts/` streamline common workflows:

- `scripts/saltstack.sh`: start/stop Salt containers, run states, or open a shell on the master.
- `scripts/puppet.sh`: manage Puppet services, follow agent logs, or trigger `puppet agent --test`.
- `scripts/ansible.sh`: control the Ansible container, run playbooks, or execute `ansible-pull`.
- `scripts/chef.sh`: start the Chef container, drop into a shell, or converge a run list.

Each script prints usage details when invoked without arguments.

Download the required images once before you start experimenting:

```bash
docker compose pull
```

## SaltStack

- Configuration lives under `saltstack/`.
- Start the master and minion:

  ```bash
  docker compose up -d salt-master salt-minion
  ```

- Accept the minion key (auto-accept is configured, but you can verify):

  ```bash
  docker compose exec salt-master salt-key --list-all
  ```

- Apply the sample state:

  ```bash
  docker compose exec salt-master salt '*' state.apply
  ```

  The state (`saltstack/states/demo/init.sls`) creates `/tmp/salt_demo.txt` on the minion.

## Puppet

- Manifests live under `puppet/code/environments/production/`.
- Start both services:

  ```bash
  docker compose up -d puppetserver puppet-agent
  ```

- The server autosigns the agent certificate (`puppet/autosign.conf`). The agent loops every 60 seconds running `puppet agent --test`, so you can watch the logs:

  ```bash
  docker compose logs -f puppet-agent
  ```

  The example manifest (`site.pp`) ensures `/tmp/puppet_demo.txt` exists on the agent container.

## Ansible Pull

- Author playbooks under `ansible/`.
- The `ansible-pull` service is kept idle so you can run ad-hoc commands:

  ```bash
  docker compose up -d ansible-pull
  docker compose exec ansible-pull bash
  ```

- Inside the container you can run `ansible-playbook` against `playbooks/local.yml`:

  ```bash
  ansible-playbook -i /workspace/inventory.ini /workspace/playbooks/local.yml
  ```

- To try a true `ansible-pull` workflow using the sample repo:

  1. Turn `ansible/pull_repo` into a Git repository on the host:

     ```bash
     cd ansible/pull_repo
     git init
     git add site.yml
     git commit -m "Initial demo playbook"
     ```

  2. Run `ansible-pull` from inside the container, pointing at the mounted repository:

     ```bash
     ansible-pull -U file:///workspace/pull_repo -d /tmp/ansible-pull -i /workspace/inventory.ini
     ```

  The demo playbook creates `/tmp/ansible_pull_repo.txt`.

## Chef Infra

- Cookbooks are under `chef/cookbooks/`.
- Start the container:

  ```bash
  docker compose up -d chef-client
  ```

- Execute Chef Infra Client in local-mode against the bundled cookbook:

  ```bash
  docker compose exec chef-client chef-client -z -c /workspace/client.rb -o demo
  ```

  This converges the `demo` cookbook and creates `/tmp/chef_demo.txt`.

  > **Tip:** If you already had the container running before switching to the Chef Workstation image, recreate it (`docker compose up -d --force-recreate chef-client`) so the updated tooling is available.

## Cleanup

Stop the environment when you are finished:

```bash
docker compose down
```

Persistent data such as Puppet certificates live inside the `puppet/agent/ssl` directory so you can destroy and recreate containers without losing state.
