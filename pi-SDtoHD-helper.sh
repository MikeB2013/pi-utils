#!/bin/bash

# Configure a Raspbian system to use an external USB drive as root filesystem.
#

# set -e

function print_version() {
    echo "pi-SDtoHD-helper.sh v 0.1"
    exit 1
}

function print_help() {
    echo "Usage: $0 -d [target device]"
    echo "    -h            Print this help"
    echo "    -v            Print version information"
    echo "    -d [device]   Specify destination device e.g. -d /dev/sda"
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    echo -e  "must be run as root. use sudo"
    exit 1
fi

# Handle arguments:
args=$(getopt -uo 'hvd:' -- $*)
[ $? != 0 ] && print_help
set -- $args

for i
do
    case "$i"
    in
        -h)
            print_help
            ;;
        -v)
            print_version
            ;;
        -d)
            target_drive="$2"
           echo "Target drive = ${2}"
            shift
            shift
            ;;
    esac
done

if [[ ! -e "$target_drive" ]]; then
    echo -e  "Target $target_drive must be existing device (use -d /dev/sd<n> to specify)"
    echo -e "WARNING: Do not connect an external USB Hard Disk whilst Pi is powered"
    exit 1
fi

#todo check if disk has been automounted, if so we need to unmount before setting up
isdiskmounted=""
isdiskmounted=$(mount |grep $target_drive)
#echo "disk mounted $isdiskmounted"
if [[ ! -z "$isdiskmounted" ]]; then
echo -e "Disk already mounted (via automount) - unmount and re-run this script"
echo -e "Mounted disk details:\n $isdiskmounted\n"
echo -e "Quitting"
exit 1

fi

echo -e "Will create new ext4 filesystem on $target_drive"
echo -e "WARNING: Any data on $target_drive will be DESTROYED."

read -p "Really proceed? (y)es / (n)o " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Quitting."
    exit 1
fi

target_partition=${target_drive}1

#check needed utilties are installed (they should be)
apt-get install  rsync parted

echo -e  "Creating $target_partition"

parted --script "$target_drive" mklabel gpt
sleep 2
#parted --script --align optimal "$target_drive" mkpart primary ext4 0% 100%
parted --script --align optimal "$target_drive" mkpart primary ext4 1MiB 100%
sleep 2

echo -e "Creating ext4 filesystem on $target_partition"
mkfs -t ext4 -L rootfs "$target_partition"
sync
echo -e "Getting partition information"

target_partition_partuuid=`blkid --match-tag PARTUUID --output value "$target_partition"`
target_partition_uuid=`blkid --match-tag UUID --output value "$target_partition"`

echo -e "Mounting $target_partition on /mnt"
mount $target_partition /mnt

echo -e "Copying root filesystem to $target_partition with rsync"
echo -e "This will take quite a while.  Please be patient!"
    rsync -avx / /mnt
sync
sync
sync
echo -e  "Configuring boot from $target_partition"

# rootdelay=5 is likely not necessary here, but does no harm.
cp /boot/cmdline.txt /boot/cmdline.txt.bak
sed -i "s/\( root=PARTUUID=*\)[^ ]*/\1${target_partition_partuuid} rootdelay=5 /" /boot/cmdline.txt
sed -i "s/\( root=\)\/[^ ]*/\1PARTUUID=${target_partition_partuuid} rootdelay=5 /" /boot/cmdline.txt
sync
echo  "Commenting out old root partition in /etc/fstab, adding new one"
# These changes are made on the new drive after copying so that they
# don't have to be undone in order to switch back to booting from the
# SD card.
sed -i -r '/\/[ \t]*ext4/s/^/#/' /mnt/etc/fstab
sync
echo "/dev/disk/by-uuid/${target_partition_uuid}    /   ext4    defaults,noatime  0       1" >> /mnt/etc/fstab
echo  "Your new root drive is currently accessible under /mnt."
echo  "You may wish to check:"
echo  "  /mnt/etc/fstab"
echo  "  /boot/cmdline.txt"
echo  "Target partition PARTUUID (/boot/cmdline.txt): $target_partition_partuuid"
echo  "Target partition UUID (/mnt/fstab): $target_partition_uuid"
echo  "Please reboot to use the new SSD/HD, type sudo reboot"
sync
exit
