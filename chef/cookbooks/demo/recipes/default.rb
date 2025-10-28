require 'yaml'

apt_update

topology_path = node['demo']['topology_path']
topology_present = ::File.exist?(topology_path)
shared_root = node['demo']['shared_root']
panelpc_share = ::File.join(shared_root, node['demo']['panelpc_share'])
message_filename = node['demo']['panelpc_message_filename']
message_file = ::File.join(panelpc_share, message_filename)
target_dir = node['demo']['distributed_target_dir']
target_file = ::File.join(target_dir, message_filename)
current_hostname = node['hostname'] || node.name

topology = begin
  if topology_present
    YAML.safe_load(::File.read(topology_path)) || {}
  else
    Chef::Log.warn("Topology file #{topology_path} not found; falling back to defaults")
    {}
  end
rescue Psych::SyntaxError => e
  Chef::Log.warn("Failed to parse topology file #{topology_path}: #{e.message}")
  {}
end

panelpc_hosts = Array(topology.dig('panelpc', 'hosts')).map(&:to_s)
qg_hosts = Array(topology.dig('qg', 'hosts')).map(&:to_s)
dv_hosts = Array(topology.dig('dv', 'hosts')).map(&:to_s)

workers_hosts = Array(topology.dig('workers', 'hosts')).map(&:to_s)

if workers_hosts.empty?
  workers_hosts = (qg_hosts + dv_hosts).uniq
end

unless topology_present
  panelpc_hosts = %w[chef-panelpc] if panelpc_hosts.empty?
  qg_hosts = %w[chef-qg-1 chef-qg-2] if qg_hosts.empty?
  workers_hosts = (qg_hosts + dv_hosts).uniq if workers_hosts.empty?
end

is_panelpc = panelpc_hosts.include?(current_hostname)
is_qg = qg_hosts.include?(current_hostname)
is_dv = dv_hosts.include?(current_hostname)
is_worker = workers_hosts.include?(current_hostname) || is_qg || is_dv

Array(node['demo']['packages']['common']).each do |pkg|
  package pkg
end

if is_panelpc
  Array(node['demo']['packages']['panelpc']).each do |pkg|
    package pkg
  end
end

if is_worker
  Array(node['demo']['packages']['workers']).each do |pkg|
    package pkg
  end
end

if is_qg
  Array(node['demo']['packages']['qg']).each do |pkg|
    package pkg
  end
end

if is_dv
  Array(node['demo']['packages']['dv']).each do |pkg|
    package pkg
  end
end

directory shared_root do
  owner 'root'
  group 'root'
  mode '0755'
end

directory panelpc_share do
  owner 'root'
  group 'root'
  mode '0755'
end

directory target_dir do
  owner 'root'
  group 'root'
  mode '0755'
  only_if { is_worker }
end

if is_panelpc
  file message_file do
    content lazy {
      worker_list = workers_hosts.empty? ? 'none' : workers_hosts.sort.join(', ')
      <<~CONTENT
        PanelPC Broadcast
        Targets: #{worker_list}

        #{node['demo']['panelpc_message'].strip}
      CONTENT
    }
    mode '0644'
  end
end

if is_worker
  file target_file do
    content lazy { ::File.exist?(message_file) ? ::File.read(message_file) : node['demo']['panelpc_message'] }
    mode node['demo']['distributed_target_mode']
    only_if { ::File.exist?(message_file) }
  end

  log 'panelpc_message_missing' do
    message "Skipping broadcast sync because #{message_file} does not exist yet"
    level :info
    not_if { ::File.exist?(message_file) }
  end
end

roles = []
roles << 'panelpc' if is_panelpc
roles << 'worker' if is_worker && !is_panelpc
roles << 'qg' if is_qg
roles << 'dv' if is_dv
roles << 'common' if roles.empty?

template '/etc/motd' do
  source 'motd.erb'
  mode '0644'
  variables(
    hostname: current_hostname,
    roles: roles.uniq,
    panelpc_hosts: panelpc_hosts.sort,
    worker_hosts: workers_hosts.sort,
    qg_hosts: qg_hosts.sort,
    dv_hosts: dv_hosts.sort
  )
end
