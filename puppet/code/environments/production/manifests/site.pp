node default {
  file { '/tmp/puppet_demo.txt':
    ensure  => file,
    content => "Managed by Puppet demo.\n",
  }
}
