class jenkins {
    package {"java-1.6.0-openjdk" : ensure => "installed" }

    package {"jenkins":
        ensure  => "installed",
        provider => "rpm",
        source => "http://pkg.jenkins-ci.org/redhat/jenkins-1.504-1.1.noarch.rpm",
    }

    service { "jenkins":
        enable  => true,
        ensure  => "running",
        hasrestart=> true,
        require => [ Package["jenkins"], Package["java-1.6.0-openjdk"] ],
    }
}
