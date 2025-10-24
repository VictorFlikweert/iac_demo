{# Trigger a highstate on minions reported by presence beacon or minion start event #}
{% set minions = [] %}
{% if data.get('new') %}
  {% set minions = data.get('new') %}
{% elif data.get('id') %}
  {% set minions = [data.get('id')] %}
{% endif %}

{% for minion_id in minions %}
run_highstate_{{ minion_id|replace('-', '_') }}:
  local.state.highstate:
    - tgt: {{ minion_id }}
    - expr_form: glob
    - retry:
        attempts: 3
        interval: 10
{% endfor %}
