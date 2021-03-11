## Preparations for Jenkins environment

This is a set of scripts to setup the Continuous Integration infrastructure for Hibernate.
The Ansible playbook does not make extensive usage of variables as we don't expect to need that: feel free to take inspiration from these but don't expect this to be a general purpose framework to setup a CI environment.

We prefer to make some assumptions and keep this simple; among others, we expect to run the public facing services on Red Hat Enterprise Linux 8, and run some build nodes on Fedora Cloud.

The primary site will run on Amazon AWS; build nodes are run on a variety of other platforms, some directly controlled, some provided by partners.

## Preparations: security

You'll need the following two private keys:
 - ~/.ssh/keys/hibernate-keys-aws.pem
 - ~/.ssh/keys/hibernate-keys-os1.pem

They are expected to be found at that path, no options given to override.
You can use different keys of course, but we won't pay your AWS bills.

## Boot the servers

You should run:
 - 1 Server to host the primary Jenkins node: start it on AWS and use a RHEL 8 image
 - N Servers to host the various Jenkins build nodes; use a recent Fedora Cloud image

Boot them using the provided 'cloud-init' script.
When booting machines from the UI, you can paste the content of 'cloud-init' into the "Customisation Script" section on the AWS console.

## Set the IP addresses

Nodes running on AWS need to be attached with the matching reserved IP addresses.
Nodes running elsewhere will need some way to allow connecting to them.

## Let it configure your servers

Now install Ansible, then the required collections:

	ansible-galaxy collection install -r requirements.yml

Then run the Ansible playbook like this:

	ansible-playbook -i hosts site.yml

### Performance Tip

When only updating the build nodes (which run on Fedora), it is recommended to enable SSH pipelining which will make things go quite a bit faster. To do so, specify pipelining = True in ansible.cfg. (This couldn't work on RHEL 7 for security reasons, it might work on RHEL 8)

You can also run the playbook on a subset of the hosts in the file using the parameter "--limit":

    ansible-playbook -i hosts site.yml --limit cislaves

If you want to have the list of IP affected without running the playbook you can use the option "--list-hosts":

    ansible-playbook -i hosts site.yml --limit cislaves --list-hosts

It is also possible to execute specific tasks using tags:

    ansible-playbook -i hosts site.yml --limit cislaves --tags "generate-script"

More details about tags can be found the ansible documentation.

## Finishing touches

The primary Jenkins node is now running, updates installed. The other nodes are ready to receive build jobs, and have all databases running locally.
Jenkins is not configured however, you'll need to manually transfer a copy of the configuration from a previous copy of these machines, or reconfigure it using the web UI.

You will also likely need to copy some private keys (to upload releases and docs) and install JDK versions or other tools which are not freely available.
Copy these to the primary node into /home/jenkins/{something}, make them owned by the `jenkins` user, and then invoke the ~/transfer-to-slaves.sh script as `jenkins`
to synchronize the tools to each slave. N.B. the script might need changes to include new tools.

## Making changes to the build nodes

The Ansible playbook is designed so it can be re-run on your existing infrastructure without undoing configuration you did on the previous step.
To make changes to the configuration of a build node, update the playbook and run the ansible-playbook command again.
When done, commit the changes here again so that next time we'll need to rebuild nodes they will include your changes.


## TL;DR Running ansible on the build nodes

ansible-playbook -i hosts site.yml --limit cislaves
ansible-playbook -i hosts site.yml --limit awscislaves
ansible-playbook -i hosts site.yml --tags generate-script

ssh ci.hibernate.org
su jenkins
cd /home/jenkins
sh transfer-ssh-to-slaves.sh
sh transfer-to-slaves.sh

