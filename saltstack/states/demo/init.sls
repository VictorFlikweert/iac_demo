{%- set panelpc_mine = salt['mine.get']('salt-master', 'panelpc_ip') %}
{%- set panelpc_ip = panelpc_mine.get('salt-master', 'UNKNOWN') %}

{%- if grains.get('type') == 'QG' %}
curl:
  pkg.installed: []
{%- endif %}

{%- if grains.get('type') == 'QG' and grains.get('role') == 'master' %}
boxes:
  pkg.installed: []
{%- endif %}

{%- if grains.get('type') in ['QG', 'VS'] %}
panelpc_ip_conf:
  file.managed:
    - name: /etc/ip.conf
    - contents: |
        {{ panelpc_ip }}
    - mode: '0644'
    - user: root
    - group: root
{%- endif %}

{%- if grains.get('type') == 'PPC' %}
refresh_panelpc_mine:
  module.run:
    - name: mine.update
{%- endif %}
