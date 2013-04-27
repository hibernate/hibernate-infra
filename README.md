# Getting started
This project is a container for a set of puppet scripts that can be used to install and start a jenkins instance with relative plugins.
It's a set of puppet configurations plus a cloudinit configuration file that can be used to prepare a machine in the cloud with the minimum configuration needed to start puppet.

The jenkins puppet module and relative dependecies are included as submodules of the current project.

## Example using AWS
Only applies to start a CI instance on Amazon Web Services's EC2; assuming you have set up the ec2-tools-api:

1. Clone the project or download the cloud-config-puppet-master.txt file:

        git clone git://github.com/hibernate/ci.hibernate.org.git

2. Launch a machine using EC2 and passing the cloud-config-puppet-master.txt file as parameter:

        ec2-run-instances ami-d0f89fb9 -t m1.large -k hibernate-keys -f cloud-config-puppet-master.txt --ebs-optimized true --block-device-mapping /dev/sda1=:500

For information on ami-d0f89fb9 or alternative choices see http://cloud-images.ubuntu.com/locator/ec2/

Since we request a server with a larger root drive, an online partition resize is performed on first boot: it will take some time before it is reachable via network.

## Use puppet without AWS
This works in theory on any VM or bare metal Linux server, but is experimental and might not work on all distributions.
Assuming puppet is already installed:

1. Clone the project

        git clone git://github.com/hibernate/ci.hibernate.org.git

2. Update the submodules

        cd ci.hibernate.org
        git submodule update --init

3. Copy the content of the folder in /etc/puppet

        rsync -rvz --exclude=.git . /etc/puppet

4. Restart the puppet master and the puppet agent

        puppet master start
        puppet --onetime --waitforcert 5 --no-daemonize --verbose
