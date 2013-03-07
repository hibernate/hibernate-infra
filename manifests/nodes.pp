node 'domu-12-31-39-06-71-37.compute-1.internal' {
  include jenkins

  package { 'mc' : ensure => installed }
  package { 'htop' : ensure => installed }
  package { 'git' : ensure => installed }

  if $operatingsystem == 'Fedora' {
    package { 'ack' : ensure => installed }
  }
}
