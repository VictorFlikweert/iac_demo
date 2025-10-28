{#-
Manage topology-aware packages, broadcast files, and MOTD for the Salt demo.
-#}
{%- set defaults = {
    'topology': {
      'panelpc': {'hosts': ['minion-panelpc']},
      'workers': {'hosts': ['minion-qg-1', 'minion-qg-2']},
      'qg': {'hosts': ['minion-qg-1', 'minion-qg-2']},
      'dv': {'hosts': []},
    },
    'shared_root': '/opt/saltdemo',
    'panelpc_share': 'panelpc',
    'panelpc_message_filename': 'broadcast.txt',
    'panelpc_message': 'PanelPC broadcast: keep nodes in sync with the latest instructions.',
    'distributed_target_dir': '/opt/saltdemo/broadcasts',
    'distributed_target_mode': '0644',
    'packages': {
      'common': ['curl', 'vim-tiny'],
      'panelpc': ['git'],
      'workers': ['jq'],
      'qg': ['tmux'],
      'dv': ['build-essential'],
    }
  } -%}
{%- set config = salt['slsutil.merge'](defaults, salt['pillar.get']('demo', {}), strategy='recurse') -%}
{%- set topology = config.get('topology', {}) -%}
{%- set default_panelpc_hosts = defaults['topology']['panelpc']['hosts'] -%}
{%- set default_qg_hosts = defaults['topology']['qg']['hosts'] -%}
{%- set panelpc_hosts = topology.get('panelpc', {}).get('hosts', []) or default_panelpc_hosts -%}
{%- set qg_hosts = topology.get('qg', {}).get('hosts', []) or default_qg_hosts -%}
{%- set dv_hosts = topology.get('dv', {}).get('hosts', []) -%}
{%- set derived_workers = (qg_hosts + dv_hosts) -%}
{%- set workers_hosts = topology.get('workers', {}).get('hosts', []) or derived_workers -%}
{%- set panelpc_hosts_sorted = panelpc_hosts | sort -%}
{%- set worker_hosts_sorted = workers_hosts | sort -%}
{%- set qg_hosts_sorted = qg_hosts | sort -%}
{%- set dv_hosts_sorted = dv_hosts | sort -%}
{%- set minion_id = grains['id'] -%}
{%- set is_panelpc = minion_id in panelpc_hosts -%}
{%- set is_qg = minion_id in qg_hosts -%}
{%- set is_dv = minion_id in dv_hosts -%}
{%- set is_worker = (minion_id in workers_hosts) or is_qg or is_dv -%}
{%- set packages = config.get('packages', {}) -%}
{%- set common_packages = packages.get('common', []) -%}
{%- set panelpc_packages = packages.get('panelpc', []) -%}
{%- set worker_packages = packages.get('workers', []) -%}
{%- set qg_packages = packages.get('qg', []) -%}
{%- set dv_packages = packages.get('dv', []) -%}
{%- set shared_root = config.get('shared_root', '/opt/saltdemo') -%}
{%- set panelpc_share = config.get('panelpc_share', 'panelpc') -%}
{%- set message_filename = config.get('panelpc_message_filename', 'broadcast.txt') -%}
{%- set panelpc_message = config.get('panelpc_message', defaults['panelpc_message']) -%}
{%- set distributed_target_dir = config.get('distributed_target_dir', '/opt/saltdemo/broadcasts') -%}
{%- set distributed_target_mode = config.get('distributed_target_mode', '0644') -%}
{%- set broadcast_source = shared_root.rstrip('/') + '/' + panelpc_share.strip('/') -%}
{%- set ns = namespace(roles=[]) -%}
{%- if is_panelpc %}{%- set ns.roles = ns.roles + ['panelpc'] -%}{%- endif -%}
{%- if is_worker and not is_panelpc %}{%- set ns.roles = ns.roles + ['worker'] -%}{%- endif -%}
{%- if is_qg %}{%- set ns.roles = ns.roles + ['qg'] -%}{%- endif -%}
{%- if is_dv %}{%- set ns.roles = ns.roles + ['dv'] -%}{%- endif -%}
{%- if ns.roles -%}
{%-   set roles_sorted = ns.roles | unique | sort -%}
{%- else -%}
{%-   set roles_sorted = ['common'] -%}
{%- endif -%}

{{ shared_root }}:
  file.directory:
    - user: root
    - group: root
    - mode: '0755'

{% if common_packages %}
common-packages:
  pkg.installed:
    - pkgs: {{ common_packages }}
    - refresh: true
{% endif %}

{% if is_panelpc %}
{% if panelpc_packages %}
panelpc-packages:
  pkg.installed:
    - pkgs: {{ panelpc_packages }}
{% endif %}

{{ broadcast_source }}:
  file.directory:
    - makedirs: True
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - file: {{ shared_root }}

panelpc-broadcast-file:
  file.managed:
    - name: {{ broadcast_source }}/{{ message_filename }}
    - source: salt://demo/files/broadcast.txt.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        panelpc_message: {{ panelpc_message | yaml_dquote }}
        panelpc_hosts: {{ panelpc_hosts_sorted }}
        worker_hosts: {{ worker_hosts_sorted }}
        current_host: {{ minion_id | yaml_dquote }}
    - require:
      - file: {{ broadcast_source }}
{% endif %}

{% if is_worker %}
{% if worker_packages %}
worker-packages:
  pkg.installed:
    - pkgs: {{ worker_packages }}
{% endif %}

{{ distributed_target_dir }}:
  file.directory:
    - makedirs: True
    - user: root
    - group: root
    - mode: '0755'

distributed-broadcast-file:
  file.managed:
    - name: {{ distributed_target_dir }}/{{ message_filename }}
    - source: salt://demo/files/broadcast.txt.j2
    - template: jinja
    - user: root
    - group: root
    - mode: {{ distributed_target_mode }}
    - context:
        panelpc_message: {{ panelpc_message | yaml_dquote }}
        panelpc_hosts: {{ panelpc_hosts_sorted }}
        worker_hosts: {{ worker_hosts_sorted }}
        current_host: {{ minion_id | yaml_dquote }}
    - require:
      - file: {{ distributed_target_dir }}
{% endif %}

{% if is_qg %}
{% if qg_packages %}
qg-packages:
  pkg.installed:
    - pkgs: {{ qg_packages }}
{% endif %}
{% endif %}

{% if is_dv %}
{% if dv_packages %}
dv-packages:
  pkg.installed:
    - pkgs: {{ dv_packages }}
{% endif %}
{% endif %}

/etc/motd:
  file.managed:
    - source: salt://demo/files/motd.txt.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        hostname: {{ minion_id | yaml_dquote }}
        roles: {{ roles_sorted }}
        panelpc_hosts: {{ panelpc_hosts_sorted }}
        worker_hosts: {{ worker_hosts_sorted }}
        qg_hosts: {{ qg_hosts_sorted }}
        dv_hosts: {{ dv_hosts_sorted }}
