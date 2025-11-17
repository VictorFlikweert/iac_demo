{%- if grains.get('type') == 'QG' %}
curl:
  pkg.installed: []
{%- endif %}

{%- if grains.get('type') == 'QG' and grains.get('role') == 'master' %}
boxes:
  pkg.installed: []
{%- endif %}
