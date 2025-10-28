default['demo']['topology_path'] = '/workspace/topology.yml'
default['demo']['shared_root'] = '/workspace/shared'
default['demo']['panelpc_share'] = 'panelpc'
default['demo']['panelpc_message_filename'] = 'broadcast.txt'

default['demo']['panelpc_message'] = <<~MESSAGE
  PanelPC broadcast: keep nodes in sync with the latest instructions.
MESSAGE

default['demo']['distributed_target_dir'] = '/opt/panelpc'
default['demo']['distributed_target_mode'] = '0644'

default['demo']['packages'] = {
  'common' => %w[curl],
  'panelpc' => %w[git],
  'workers' => %w[jq],
  'qg' => %w[tmux],
  'dv' => %w[build-essential]
}
