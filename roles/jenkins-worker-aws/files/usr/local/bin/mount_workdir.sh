#!/bin/bash -e
# Mounts the first found AWS instance store device as $1

devices=('/dev/nvme1n1' '/dev/xvdb' '/dev/xvdc' '/dev/xvdd' '/dev/xvde')
mountpoint="$1"

mount_device()
{
	device="$1"
	if [ ! -z "$(lsblk -o MOUNTPOINTS "$device" | tail -n +2)" ]
	then
		echo 2>&1 "Device $device is already mounted; aborting."
		exit 1
	fi
	if [ ! "xfs" = "$(lsblk -o FSTYPE /dev/nvme1n1 | tail -n +2)" ]
	then
		mkfs -t xfs "$device"
	fi
	mkdir -p "$mountpoint"
	mount -t xfs "$device" "$mountpoint"
	echo 2>&1 "Mounted $device to $mountpoint"
}

mounted=0
for device in "${devices[@]}"
do
		if [ -b "$device" ]
		then
				mount_device "$device"
				mounted=1
				break
		fi
done

if (( !mounted ))
then
	echo 2>&1 "Did not find any device among ${devices[*]}"
	exit 1
fi

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

echo 2>&1 "Initialized directory structure in $mountpoint"
