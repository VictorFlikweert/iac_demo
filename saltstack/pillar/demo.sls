demo:
  topology:
    panelpc:
      hosts:
        - minion-panelpc
    workers:
      hosts:
        - minion-qg-1
        - minion-qg-2
    qg:
      hosts:
        - minion-qg-1
        - minion-qg-2
    dv:
      hosts: []
  shared_root: /opt/saltdemo
  panelpc_share: panelpc
  panelpc_message_filename: broadcast.txt
  panelpc_message: |
    PanelPC broadcast: keep nodes in sync with the latest instructions.
  distributed_target_dir: /opt/saltdemo/broadcasts
  distributed_target_mode: '0644'
  packages:
    common:
      - curl
      - vim
    panelpc:
      - git
    workers:
      - jq
    qg:
      - tmux
    dv:
      - build-essential
