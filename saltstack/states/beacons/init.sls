sync_beacons:
  module.run:
    - name: saltutil.sync_beacons

state_metrics_beacon_config:
  file.managed:
    - name: /etc/salt/minion.d/beacons.conf
    - user: root
    - group: root
    - mode: '0644'
    - contents: |
        beacons:
          state_metrics:
            interval: 15
            pushgateway: http://pushgateway:9091
            job: salt_state
