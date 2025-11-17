include:
  - common
{% if 'panelpc' in grains.get('roles', []) %}
  - boxes
{% endif %}
  - transfer
{% if grains.get('run_audit', False) %}
  - audit
{% endif %}
