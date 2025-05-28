#!/bin/bash -e
# Creates the necessary directories in instance storage

function log() {
	echo 2>&1 "${@}"
}

mountpoint="$1"

{% if ansible_hostname == "jenkins-worker" %}

log "Initializing directory structure for Jenkins workers in '$mountpoint'"

mkdir -p $mountpoint/containers
chmod 0700 $mountpoint/containers
# https://github.com/containers/podman/blob/main/troubleshooting.md#11-changing-the-location-of-the-graphroot-leads-to-permission-denied
# Ignore failures because this command doesn't like being called a second time (e.g. after a reboot)
semanage fcontext -a -e /var/lib/containers $mountpoint/containers || true
restorecon -R -v $mountpoint/containers

mkdir -p $mountpoint/jenkins
mkdir -p $mountpoint/jenkins/.m2
mkdir -p $mountpoint/jenkins/.gradle
chmod -R 0755 $mountpoint/jenkins
chown -R jenkins:jenkins $mountpoint/jenkins

log "Done"

{% elif ansible_hostname == "ci-nexus-proxy" %}

log "Initializing directory structure for Nexus proxy in '$mountpoint'"

# we put nexus/jdk executables in this directory,
# hence once we want to run them through a service (systemd)
# we have to make sure that SElinux is not going to be in the way and it would allow execution of the files in these dirs:
mkdir -p $mountpoint/nexus-service
chown fedora:fedora $mountpoint/nexus-service
chmod -R 0755 $mountpoint/nexus-service

semanage fcontext -a -t bin_t "$mountpoint/nexus-service"
restorecon -R -v $mountpoint/nexus-service

log "Done"

{% endif %}
