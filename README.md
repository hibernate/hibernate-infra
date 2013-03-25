# Getting started
This project is a container for a set of puppet scripts that can be used to install and start a jenkins instance with relative plugins.
It's a set of puppet configurations plus a cloudinit configuration file that can be used to prepare a machine in the cloud with the minimum configuration needed to start puppet.

The jenkins puppet module and relative dependecies are included as submodules of the current project.

## Example using EC2
Assuming you have set up the ec2-tools-api:

1. Clone the project or download the cloud-config-puppet-master.txt file:

        git clone git://github.com/hibernate/jenkins-servers-config.git

2. Launch a machine using EC2 and passing the cloud-config-puppet-master.txt file as parameter:

        ec2-run-instances ami-7539b41c -t t1.micro -k security-key-name -f cloud-config-puppet-master.txt

## Use puppet without cloudinit
Assuming puppet is already installed:

1. Clone the project

        git clone git://github.com/hibernate/jenkins-servers-config.git

2. Update the submodules

        cd jenkins-servers-config
        git submodule update --init

3. Copy the content of the folder in /etc/puppet

        rsync -rvz --exclude=.git . /etc/puppet

4. Restart the puppet master and the puppet agent

        puppet master start
        puppet --onetime --waitforcert 5 --no-daemonize --verbose
