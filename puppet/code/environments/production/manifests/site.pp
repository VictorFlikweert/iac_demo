node default {
  $os_family = $facts['os']['family']

  if $os_family == 'Debian' {
    exec { 'apt-update':
      command => '/usr/bin/apt-get update',
      path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      unless  => '/usr/bin/test -f /var/lib/apt/periodic/update-success-stamp',
      before  => Package['curl'],
    }
  }

  package { 'curl':
    ensure => installed,
  }
}
