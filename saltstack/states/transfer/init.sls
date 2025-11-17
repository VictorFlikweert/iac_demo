{% set roles = grains.get('roles', []) %}
{% set note_source = 'salt://transfers/panelpc-note.txt' %}

{% if 'panelpc' in roles %}
panelpc_transfer_dir:
  file.directory:
    - name: /opt/panelpc
    - mode: '0755'

panelpc_transfer_file:
  file.managed:
    - name: /opt/panelpc/from_panelpc.txt
    - source: {{ note_source | tojson }}
    - mode: '0644'
    - require:
      - file: panelpc_transfer_dir
{% endif %}

{% if 'worker' in roles %}
worker_transfer_file:
  file.managed:
    - name: /tmp/panelpc-note.txt
    - source: {{ note_source | tojson }}
    - user: root
    - group: root
    - mode: '0644'
{% endif %}
