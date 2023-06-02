#!/bin/bash
set -e # Stop if any error happenned
if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: ./mkimage <grub.cfg file> <rtems binary file>"
        echo "Example: sudo ./mkimage grub.cfd build-x86/hello.exe"
        echo "Please update the grub.cfg based on rtems binary name"
        exit -1
fi
image="rtems-boot.img"
# Hack to make everything owned by the original user.
user=`who am i | awk '{print $1}'`
group=`groups $user | awk '{print $3}'`

# Create the actual disk image - 15MB
dd if=/dev/zero of=${image} bs=512 count=32130 2>/dev/null
chown ${user}:${group} ${image}

# Setup the loopback device, and reture the devie name.
lodev=`losetup -f --show ${image}`
trap 'losetup -d ${lodev}; exit $?' INT TERM EXIT
loname=${lodev##*/}

# Make the partition table, partition and set it bootable.
parted -a minimal --script ${lodev} mklabel msdos mkpart primary ext4 1M 100% \
    set 1 boot on 

# Get the start sectors.
start=`fdisk -lu ${lodev} | grep "${loname}p1" | awk '{ print $3}'`
# Find the first unused loop device.
lonxt=`losetup -f`
# Create a loop device for this partition, like /dev/sda and /dev/sda0 work.
losetup -o $(expr 512 \* ${start}) ${lonxt} ${lodev}
trap 'losetup -d ${lonxt}; losetup -d ${lodev}; exit $?' INT TERM EXIT

# Make an ext2 filesystem on the first partition.
mkfs.ext4 ${lonxt} &>/dev/null
# Mount the filesystem via loopback.
mount ${lonxt} /mnt
trap 'umount /mnt; losetup -d ${lonxt}; losetup -d ${lodev}; exit $?' INT TERM EXIT
mkdir -p /mnt/boot/grub
#echo 'source (hd0,msdos1)/grub.cfg'>/mnt/boot/grub/grub.cfg
cp $1 /mnt/boot/grub/grub.cfg

mkdir -p /mnt/boot/grub/i386-pc
cp /usr/lib/grub/i386-pc/* /mnt/boot/grub/i386-pc
cp  $2 /mnt/boot/$(basename $2) 
# Make a bootable image of GRUB.
grub-mkimage -d /usr/lib/grub/i386-pc -O i386-pc --output=core.img \
        --prefix=\(,msdos1\)/boot/grub ext2 part_msdos biosdisk search_fs_uuid
mv core.img /mnt/boot/grub/i386-pc
# Set up a device to boot using GRUB.
grub-bios-setup --allow-floppy  --force --directory=/mnt/boot/grub/i386-pc \
        --device-map= ${lodev}

sync
trap - INT TERM EXIT
umount /mnt
losetup -d ${lonxt}
losetup -d ${lodev}
