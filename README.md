## Preparations for Jenkins environment

This is a set of scripts to setup the Continuous Integration infrastructure for Hibernate.
The Ansible playbook does not make extensive usage of variables as we don't expect to need that: feel free to take inspiration from these but don't expect this to be a general purpose framework to setup a CI environment.

We prefer to make some assumptions and keep this simple;
among others, we expect to run the public facing services on Red Hat Enterprise Linux 8,
and run some Jenkins worker nodes on Fedora Cloud.

The primary site will run on Amazon AWS; Jenkins worker nodes are run on a variety of other platforms, some directly controlled, some provided by partners.
The websites and the Jenkins coordinator node will run on permanent instances on Amazon AWS,
while most Jenkins worker nodes will run on AWS EC2 Spot instances launched by the Jenkins AWS EC2 plugin,
and some Jenkins worker nodes will be managed by partners.

## Preparations: AWS launch templates

If your SSH key was never used to build the servers,
you will need to add the public key to the `cloud-init` file at the root of this git repository.
Then update the following launch templates owned by the `hibernate` organization on AWS accordingly,
by setting the "user data" to the content of the `cloud-init` file:

 - `jenkins-ci-coordinator`
 - `jenkins-ci-worker-ami-building`

You can use a different organization and launch templates of course, but we won't pay your AWS bills.

## Boot the servers

You should run:
 - 1 instance to host the Jenkins coordinator node.
   Start it on AWS and use the `jenkins-ci-coordinator` launch template (a RHEL 8 image).
 - 1 instance to create an AMI for the various Jenkins worker nodes,
   which will then be used by the Jenkins AWS EC2 plugin to spawn slaves on demand.
   Start it on AWS and use the `jenkins-ci-worker-ami-building` launch template.

Boot them using the provided 'cloud-init' script.
When booting machines from the UI, you can paste the content of 'cloud-init' into the "Customisation Script" section on the AWS console.

## Update the inventory file (server addresses and keys)

You will need to update the inventory file `hosts` to point to the servers you just launched.
Gather the public IP address or public DNS for each server,
and paste it in the 'hosts' file in the appropriate section:

- The address of the AWS Jenkins CI coordinator node in `cimaster`
- The address of the AWS Jenkins CI worker node in `awscislaves`

Make sure to update the paths to the private keys as necessary.

Do not commit these changes unless your changes may be useful to other users.

## Let it configure your servers

Now install Ansible, then the required collections:

	ansible-galaxy collection install -r requirements.yml

Then run the Ansible playbook like this:

	ansible-playbook -i hosts site.yml

### Performance Tip

When only updating the build nodes (which run on Fedora), it is recommended to enable SSH pipelining which will make things go quite a bit faster. To do so, specify pipelining = True in ansible.cfg. (This couldn't work on RHEL 7 for security reasons, it might work on RHEL 8)

You can also run the playbook on a subset of the hosts in the file using the parameter "--limit":

    ansible-playbook -i hosts site.yml --limit awscislaves

If you want to have the list of IP affected without running the playbook you can use the option "--list-hosts":

    ansible-playbook -i hosts site.yml --limit awscislaves --list-hosts

It is also possible to execute specific tasks using tags:

    ansible-playbook -i hosts site.yml --limit awscislaves --tags "generate-script"

More details about tags can be found the ansible documentation.

## Finishing touches

The Jenkins coordinator node is now running, updates installed.

Jenkins is not configured however: you'll need to manually transfer a copy of the configuration
from a previous master machine or reconfigure it using the web UI.

The Jenkins slave is also running and up to date, but needs to be turned into an AMI
so that Jenkins can spin up slaves dynamically.
Create an image from the `Instances` panel of the AWS EC2 console:
select the instance, then click `Actions > Image > Create Image`.
Do not forget to update the AMI in the Jenkins AWS EC2 plugin configuration.

## Making changes to the build nodes

The Ansible playbook is designed so it can be re-run on your existing infrastructure without undoing configuration you did on the previous step.
To make changes to the configuration of a build node, update the playbook and run the ansible-playbook command again.
When done, commit the changes here again so that next time we'll need to rebuild nodes they will include your changes.


## TL;DR Running ansible on the build nodes

ansible-playbook -i hosts site.yml --limit awscislaves
ansible-playbook -i hosts site.yml --tags generate-script

