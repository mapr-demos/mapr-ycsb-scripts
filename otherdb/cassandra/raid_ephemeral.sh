#!/bin/bash
#
# this script will attempt to detect any ephemeral drives on an EC2 node and create a RAID-0 stripe
# mounted at /mnt. It should be run early on the first boot of the system.
#
# Beware, This script is NOT fully idempotent.
#

METADATA_URL_BASE="http://169.254.169.254/2012-01-12"

USEDISKS=""
while [[ $# -gt 1 ]]
do
    key="$1"
    case $key in
    -d|--disks)
        USEDISKS="$2"
        shift # past argument
	;;
    esac
done

yum -y -d0 install mdadm curl

# Configure Raid - take into account xvdb or sdb
root_drive=`df -h | grep -v grep | awk 'NR==2{print $1}'`

if [ "$root_drive" == "/dev/xvda1" ]; then
  echo "Detected 'xvd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='xvd'
else
  echo "Detected 'sd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='sd'
fi

# if the user hasn't passed any disks,
# figure out how many ephemerals we have by querying the metadata API, and then:
#  - convert the drive name returned from the API to the hosts DRIVE_SCHEME, if necessary
#  - verify a matching device is available in /dev/
drives=""
ephemeral_count=0
if [ "$USEDISKS" != "" ]; then
    echo "using supplied disk list: " $USEDISKS
    drives=$USEDISKS
    for d in $drives; do
        ephemeral_count=$((ephemeral_count + 1 ))
    done
else
    ephemerals=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/ | grep ephemeral)
    for e in $ephemerals; do
      echo "Probing $e .."
      device_name=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/$e)
      # might have to convert 'sdb' -> 'xvdb'
      device_name=$(echo $device_name | sed "s/sd/$DRIVE_SCHEME/")
      device_path="/dev/$device_name"
    
      # test that the device actually
      # exists since you can request more ephemeral drives than are available
      # for an instance type and the meta-data API will
      # happily tell you it exists when it really does not.
      if [ -b $device_path ]; then
        echo "Detected ephemeral disk: $device_path"
        drives="$drives $device_path"
        ephemeral_count=$((ephemeral_count + 1 ))
      else
        echo "Ephemeral disk $e, $device_path is not present. skipping"
      fi
    done
    
    if [ "$ephemeral_count" = 0 ]; then
      echo "No ephemeral disk detected. exiting"
      exit 0
    fi
    
    # ephemeral0 is typically mounted for us already. umount it here
    umount /mnt
fi


# overwrite first few blocks in case there is a filesystem, otherwise mdadm will prompt for input
for drive in $drives; do
  dd if=/dev/zero of=$drive bs=4096 count=1024
done

partprobe
mdadm --create --verbose /dev/md0 --level=0 -c256 --raid-devices=$ephemeral_count $drives
echo DEVICE $drives | tee /etc/mdadm.conf
mdadm --detail --scan | tee -a /etc/mdadm.conf
blockdev --setra 65536 /dev/md0
mkfs.xfs -s size=4096 -d sw=$ephemeral_count -d su=262144 /dev/md0 
mount -t xfs -o noatime /dev/md0 /mnt

# Remove xvdb/sdb from fstab
if [ "$USEDISKS" == "" ]; then
    chmod 777 /etc/fstab
    sed -i "/${DRIVE_SCHEME}b/d" /etc/fstab
fi

# Make raid appear on reboot
echo "/dev/md0 /mnt xfs noatime 0 0" | tee -a /etc/fstab
