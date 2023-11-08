#!/bin/bash -e
# Mounts the first found AWS instance store device as $1

function log() {
	echo 2>&1 "${@}"
}

function device_for_mountpoint() {
	mount | awk "{if (\$3 == \"$1\") {print \$1; exit 0}}"
}

function devices() {
	lsblk --nodeps --noheading -o PATH | sort
}

function mountpoint_for_device() {
	mount | awk "{if (\$1 == \"$1\") {print \$3; exit 0}}"
}

function partitions_for_device() {
	lsblk --noheading -o PATH "$1" | { grep -v "^$1$" || true; } | tr '\n' ' '
}

function fstype_for_device() {
	lsblk --noheading --nodeps -o FSTYPE "$1"
}

function mount_device() {
	device="$1"
	log "Mounting '$device' on '$mountpoint'."
	if ! [[ "xfs" == "$(fstype_for_device "$device")" ]]
	then
		mkfs -t xfs "$device"
	fi
	mkdir -p "$mountpoint"
	mount -t xfs "$device" "$mountpoint"
	log "Mounted '$device' on '$mountpoint'"
}

mountpoint="$1"

current_device_for_mountpoint="$(device_for_mountpoint "$mountpoint")"
if [[ -n "$current_device_for_mountpoint" ]]
then
	log "Directory '$1' is already the mountpoint for '$current_device_for_mountpoint'; skipping."
	exit 0
fi

mounted=0
candidate_devices=()
for device in $(devices)
do
	current_mountpoint_for_device="$(mountpoint_for_device "$device")"
	current_partitions_for_device="$(partitions_for_device "$device")"
	if ! [[ "$device" == /dev/nvme* || "$device" == /dev/xvd* ]]
	then
		log "Ignoring device '$device' because its name doesn't match any expected pattern."
	elif [[ -n "$current_mountpoint_for_device" ]]
	then
		log "Ignoring device '$device' because it is already mounted on '$current_mountpoint_for_device'."
	elif [[ -n "$current_partitions_for_device" ]]
	then
		log "Ignoring device '$device' because it is already has partitions: $current_partitions_for_device."
	else
		candidate_devices=("${candidate_devices[@]}" "$device")
	fi
done

log "Candidate devices: ${candidate_devices[*]}"

device_to_mount=
case "${#candidate_devices[@]}" in
	"0")
		log "No candidate device found; aborting."
		exit 1
		;;
	"1")
		;;
	*)
		log "Multiple candidate devices found: selecting the first one and hoping for the best."
		;;
esac

device_to_mount="${candidate_devices[0]}"
mount_device "$device_to_mount"

log "Initializing directory structure in '$mountpoint'"

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
