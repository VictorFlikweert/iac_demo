{% set roles = grains.get('roles', []) %}

{% if 'worker' in roles %}
panelpc_note_stats:
  module.run:
    - name: file.stats
    - m_name: /tmp/panelpc-note.txt

common_package_versions:
  module.run:
    - name: pkg.version
    - pkgs:
      - curl
      - vim-tiny
{% endif %}
