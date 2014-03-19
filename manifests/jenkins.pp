node default {

  include jenkins
  include mongodb

  package {
    [ 'httpd', 'wget', 'sudo', 'vim-minimal', 'mc', 'htop', 'git', 'maven', 'openjdk-7-jdk', 'sendmail', 'poxml', 'docker-io' ] : ensure => latest
  }

  file { "apache2-config":
    path => "/etc/httpd/conf.d/000-default.conf",
    source => "puppet:///apache2-config/sites-enabled/default",
    owner => "root",
    group => "root",
    mode => 644,
    require => Package["httpd"],
  }

  if $operatingsystem == 'Fedora' {
    package { 'ack' : ensure => installed }
  }

  if $operatingsystem == 'Ubuntu' {
    package { 'ack-grep' : ensure => installed }
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

  if $operatingsystem == 'Fedora' {
    file { "jenkins-service-conf":
      path => "/etc/sysconfig/jenkins",
      source => "puppet:///jenkins-config/jenkins-conf-fedora",
      ensure => present,
      notify => Service["jenkins"],
    }
  }

  if $operatingsystem == 'Ubuntu' {
    file { "jenkins-service-conf":
      path => "/etc/default/jenkins",
      source => "puppet:///jenkins-config/jenkins-conf-ubuntu",
      ensure => present,
      notify => Service["jenkins"],
    }
  }

  file { "git-jenkins-plugin":
    path => "/var/lib/jenkins/hudson.plugins.git.GitSCM.xml",
    source => "puppet:///jenkins-config/hudson.plugins.git.GitSCM.xml",
    ensure => present,
  }

  file { "ant-jenkins-plugin":
    path => "/var/lib/jenkins/hudson.tasks.Ant.xml",
    source => "puppet:///jenkins-config/hudson.tasks.Ant.xml",
    ensure => present,
  }

  file { "maven-jenkins-plugin":
    path => "/var/lib/jenkins/hudson.tasks.Maven.xml",
    source => "puppet:///jenkins-config/hudson.tasks.Maven.xml",
    ensure => present,
  }

  file {".ssh":
    path => "/root/.ssh",
    owner => "root",
    group => "root",
    mode => 700,
    ensure => directory,
  }

  file { "ssh-team-keys":
    path => "/root/.ssh/authorized_keys",
    require => File[".ssh"],
    source => "puppet:///ssh-config/root_authorized_keys",
    ensure => present,
    owner => "root",
    group => "root",
    mode => 600,
  }

  jenkins::plugin {
        "analysis-collector" : ;
        "analysis-core" : ;
        "audit-trail" : ;
        "build-timeout" : ;
        "checkstyle" : ;
        "credentials" : ;
        "embeddable-build-status" : ;
        "envinject" : ;
        "findbugs" : ;
        "ghprb" : ;
        "git" : ;
        "git-client" : ;
        "github" : ;
        "github-api" : ;
        "github-oauth" : ;
        "gitlab-hook" : ;
        "gradle" : ;
        "gravatar" : ;
        "heavy-job" : ;
        "htmlpublisher" : ;
        "instant-messaging" : ;
        "ircbot" : ;
        "jacoco" : ;
        "javadoc" : ;
        "jira" : ;
        "maven-plugin" : ;
        "monitoring" : ;
        "pmd" : ;
        "simple-theme-plugin" : ;
        "tasks" : ;
        "twitter" : ;
  }

}
