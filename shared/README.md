# Shared files folder

This folder is synchronized into Ansible hosts.
Put the `*.rpm` files here that need to be installed on all hosts.

## Uptycs

Go to https://edr-tools.platformops.ciso.ibm.com/download-sensors, choose the `Think (WW)` tenant,
`Fedora x86-64` as Platform, the `assets` asset group and the `N` version. Copy the downloaded file into this folder.

Any filename matching `*uptycs*.rpm` is picked up, so you can just drop the newly downloaded file here;
remove the older one, as the playbook fails if several files match.
The folder and pattern are configured in `ansible/group_vars/all.yml`.

The RPM only needs to be present when you want to install or upgrade Uptycs:

* If the file is here, the playbook copies it to the host and installs it (upgrading any older version).
* If the file is missing but Uptycs is already installed on the host, install is skipped and the playbook
  just checks/configures the existing installation.
* If the file is missing and Uptycs is not installed on the host, all Uptycs tasks are skipped with a warning.