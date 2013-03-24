node default {

  include jenkins
  include mongodb

  package {
    [ 'wget', 'vim', 'mc', 'htop', 'git', 'maven', 'tree' ] : ensure => latest
  }

  if $operatingsystem == 'Fedora' {
    package { 'ack' : ensure => installed }
  }

  if $operatingsystem == 'Ubuntu' {
    package { 'ack-grep' : ensure => installed }
  }

  jenkins::plugin {
        "git" : ;
        "git-client" : ;
        "maven-plugin" : ;
        "jira" : ;
        "gitlab-hook" : ;
        "ghprb" : ;
  }

  File {
    owner => "jenkins",
    group => "jenkins",
    mode => 770,
  }

  file {"jenkins_home":
    path => "/home/jenkins",
    ensure => directory,
  }

  file {".m2":
    path => "/home/jenkins/.m2",
    ensure => directory,
    require => File["jenkins_home"],
  }

  file { ".m2/settings.xml":
    path => "/home/jenkins/.m2/settings.xml",
    source => "puppet:///maven-config/settings.xml",
    ensure => present,
    require => [ Package["maven"], File[".m2"] ],
  }

}
