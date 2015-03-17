## Preparations for Jenkins environment

- Expects Red Hat based hosts, probably requires Fedora 21

Then run the playbook, like this:

	ansible-playbook -i hosts --private-key=~/.ssh/keys/hibernateteam.pem site.yml

