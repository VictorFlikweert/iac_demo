class demo (
  Hash $topology = {},
  Hash $packages = {},
  String $shared_root = '/workspace/shared',
  String $panelpc_share = 'panelpc',
  String $panelpc_message_filename = 'broadcast.txt',
  String $panelpc_message = 'PanelPC broadcast: keep nodes in sync with the latest instructions.',
  String $distributed_target_dir = '/opt/panelpc',
  String $distributed_target_mode = '0644',
) {
  $hostname    = $facts['networking']['hostname']
  $os_family   = $facts['os']['family']

  $panelpc_entry = $topology['panelpc'] ? {
    undef   => {},
    default => $topology['panelpc'],
  }
  $qg_entry = $topology['qg'] ? {
    undef   => {},
    default => $topology['qg'],
  }
  $dv_entry = $topology['dv'] ? {
    undef   => {},
    default => $topology['dv'],
  }
  $workers_entry = $topology['workers'] ? {
    undef   => {},
    default => $topology['workers'],
  }

  $panelpc_hosts_raw = Array($panelpc_entry['hosts'])
  $qg_hosts_raw      = Array($qg_entry['hosts'])
  $dv_hosts          = Array($dv_entry['hosts'])
  $workers_hosts_raw = Array($workers_entry['hosts'])

  $panelpc_hosts = ($panelpc_hosts_raw == []) ? {
    true  => ['panelpc'],
    false => $panelpc_hosts_raw,
  }

  $qg_hosts = ($qg_hosts_raw == []) ? {
    true  => ['qg-1', 'qg-2'],
    false => $qg_hosts_raw,
  }

  $derived_workers = unique($qg_hosts + $dv_hosts)

  $workers_hosts = ($workers_hosts_raw == []) ? {
    true  => $derived_workers,
    false => $workers_hosts_raw,
  }

  $is_panelpc = $hostname in $panelpc_hosts
  $is_qg      = $hostname in $qg_hosts
  $is_dv      = $hostname in $dv_hosts
  $is_worker  = ($hostname in $workers_hosts) or $is_qg or $is_dv

  $panelpc_role = $is_panelpc ? {
    true  => ['panelpc'],
    false => [],
  }
  $worker_role = (($is_worker and !$is_panelpc)) ? {
    true  => ['worker'],
    false => [],
  }
  $qg_role = $is_qg ? {
    true  => ['qg'],
    false => [],
  }
  $dv_role = $is_dv ? {
    true  => ['dv'],
    false => [],
  }

  $roles_combined = $panelpc_role + $worker_role + $qg_role + $dv_role

  $roles = ($roles_combined == []) ? {
    true  => ['common'],
    false => unique($roles_combined),
  }

  if $os_family == 'Debian' {
    exec { 'apt-update':
      command => '/usr/bin/apt-get update',
      path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      unless  => '/usr/bin/test -f /var/lib/apt/periodic/update-success-stamp',
      returns => [0, 100],
    }
    Exec['apt-update'] -> Package <| |> 
  }

  $common_packages  = Array($packages['common'])
  $panelpc_packages = Array($packages['panelpc'])
  $worker_packages  = Array($packages['workers'])
  $qg_packages      = Array($packages['qg'])
  $dv_packages      = Array($packages['dv'])

  package { $common_packages:
    ensure => installed,
  }

  if $is_panelpc {
    package { $panelpc_packages:
      ensure => installed,
    }
  }

  if $is_worker {
    package { $worker_packages:
      ensure => installed,
    }
  }

  if $is_qg {
    package { $qg_packages:
      ensure => installed,
    }
  }

  if $is_dv {
    package { $dv_packages:
      ensure => installed,
    }
  }

  $panelpc_share_path = "${shared_root}/${panelpc_share}"
  $message_file       = "${panelpc_share_path}/${panelpc_message_filename}"
  $target_file        = "${distributed_target_dir}/${panelpc_message_filename}"

  file { $shared_root:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  if $is_panelpc {
    file { $panelpc_share_path:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    file { $message_file:
      ensure  => file,
      content => epp('demo/broadcast.epp', {
        'panelpc_message' => $panelpc_message,
        'worker_hosts'    => sort($workers_hosts),
        'panelpc_hosts'   => sort($panelpc_hosts),
        'current_host'    => $hostname,
      }),
      mode    => '0644',
      require => File[$panelpc_share_path],
    }
  }

  if $is_worker {
    file { $distributed_target_dir:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    file { $target_file:
      ensure  => file,
      content => epp('demo/broadcast.epp', {
        'panelpc_message' => $panelpc_message,
        'worker_hosts'    => sort($workers_hosts),
        'panelpc_hosts'   => sort($panelpc_hosts),
        'current_host'    => $hostname,
      }),
      mode    => $distributed_target_mode,
      require => File[$distributed_target_dir],
    }
  }

  file { '/etc/motd':
    ensure  => file,
    content => epp('demo/motd.epp', {
      'hostname'      => $hostname,
      'roles'         => sort($roles),
      'panelpc_hosts' => sort($panelpc_hosts),
      'worker_hosts'  => sort($workers_hosts),
      'qg_hosts'      => sort($qg_hosts),
      'dv_hosts'      => sort($dv_hosts),
    }),
    mode    => '0644',
  }
}
