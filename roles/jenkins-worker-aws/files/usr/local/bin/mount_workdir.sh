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

mkdir -p $mountpoint/docker
chmod 0600 $mountpoint/docker

mkdir -p $mountpoint/jenkins
chmod 0755 $mountpoint/jenkins
chown jenkins:jenkins $mountpoint/jenkins

echo 2>&1 "Initialized directory structure in $mountpoint"
