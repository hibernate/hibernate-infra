## Preparations for Jenkins environment

This is a set of scripts to setup the Continuous Integration infrastructure for Hibernate.
The Ansible playbook does not make extensive usage of variables as we don't expect to need that: feel free to take inspiration from these but don't expect this to be a general purpose framework to setup a CI environment.

We prefer to make some assumptions and keep this simple; among others, we expect to run the public facing services on Red Hat Enterprise Linux 7.1, and run some more slaves on Fedora 21 Cloud.

The primary site will run on Amazon AWS; slaves are run on an highly experimental OpenStack cluster within Red Hat called OS1, kindly sponsored by Red Hat, to keep our build and test costs minimal.
OS1 is regularly reinstalled and runs bleeding edge cloud software on experimental operating system builds, so the initialization and configuration of the slave nodes is automated with more care than the master node running on AWS.

## Preparations: security

You'll need the following two private keys:
 - ~/.ssh/keys/hibernate-keys-aws.pem
 - ~/.ssh/keys/hibernate-keys-os1.pem

They are expected to be found at that path, no options given to override.
You can use different keys of course, but we won't pay your AWS bills.

## Boot the servers

You should run:
 - 1 Server to host the master Jenkins node, start it on AWS and use a RHEL 7.1 image
 - N Servers to host the various Jenkins slaves; start these on OS1 public, use a Fedora 21 Cloud image

Boot them using the provided 'cloud-init' script.
When booting machines from the UI, you can paste the content of 'cloud-init' into the "Customisation Script" section on the OpenStack console.

## Set the IP addresses

You might need to assign public IP addressed to the machines running on OpenStack.
Then gather all IP addresses, and paste them in the 'hosts' file in the respective sections: OpenStack addresses in 'cislaves', and the AWS master address in 'cimaster'.

## Let it configure your servers

Now install Ansible, then run the Ansible playbook like this:

	ansible-playbook -i hosts site.yml

### Performance Tip

When only updating the slave nodes (which run on Fedora), it is recommended to enable SSH pipelining which will make things go quite a bit faster. To do so, specify pipelining = True in ansible.cfg.
You can execute operations only on the slave nodes via the --limit parameter:

    ansible-playbook -i hosts site.yml --limit cislaves

## Finishing touches

The Jenkins master node is now running, updates installed. The slaves are ready to receive build jobs, and have all databases running locally.
Jenkins is not configured however, you'll need to manually transfer a copy of the configuration from a previous master machine or reconfigure it using the web UI.

## Making changes to the slaves

The Ansible playbook is designed so it can be re-run on your existing infrastructure without undoing configuration you did on the previous step.
To make changes to the configuration of a slave, update the playbook and run the ansible-playbook command again.
When done, commit the changes here again so next time you'll rebuild identical slaves.
