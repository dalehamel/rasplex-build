#!/bin/bash
scriptdir=$(cd `dirname $0` && pwd)
payload="/rpi"  
version=`cat $payload/image-version | cut -d : -f 1`
outname="rasplex-$version.img" # output image
payloadarch="$payload/rasplex-stage4.tar.bz2" #archive to use for stage 4 
rootmount="/mnt/rasproot"
bootmount="/mnt/raspboot"
s3dir="/mnt/plex-rpi"
firmwaredir="$scriptdir/firmware"

blocksize=4096
buffersize=350 # in MB, spare space to leave on root
bootsize=30 #in MB size of boot partition
swapsize=170 #in MB size of swap

#caclulate the block size required for the image
otherparts=`echo "$buffersize + $bootsize + $swapsize" | bc`
MBtoB=`echo "1024*1024" | bc`
otherbytes=`echo "$otherparts * $MBtoB" | bc`
otherblocks=`echo "$otherbytes/$blocksize" | bc`

payloadbytes=`du -bs $payload |  tr -s [:space:] ":" | cut -d ":" -f 1` #in bytes
payloadportagebytes=`du -bs ${payload}/usr/portage |  tr -s [:space:] ":" | cut -d ":" -f 1` #in bytes
plexdevbytes=`du -bs ${payload}/root/plex-home-theater |  tr -s [:space:] ":" | cut -d ":" -f 1` #in bytes
linuxdevbytes=`du -bs ${payload}/usr/src |  tr -s [:space:] ":" | cut -d ":" -f 1` #in bytes
netpayloadbytes=`echo "$payloadbytes - ( $payloadportagebytes + $plexdevbytes + $linuxdevbytes )" | bc`
netpayloadblocks=`echo "$netpayloadbytes/$blocksize " | bc`

totalsize=`echo "$netpayloadbytes + $otherbytes" | bc`
totalblocks=`echo "$netpayloadblocks + $otherblocks" | bc`

echo "Other size $otherbytes B, $otherblocks blocks"
echo "Payload size $payloadbytes B, $payloadblocks blocks"
echo "Portage size $payloadportagebytes B, $payloadblocks blocks"
echo "Net payload size $netpayloadbytes B, $netpayloadblocks blocks"
echo "Total blocks size $totalsize B, $totalblocks blocks"
echo "Using firmware at $firmwaredir"
echo -e "\n\n"
echo "Creating virtual block device $outname..."

#create a virtual block device of the right size
dd if=/dev/zero of=$outname bs=$blocksize count=$totalblocks

#initialize a partition table on the virtual block device, and 
#create the appropriate partition table entries

fdisk -u $outname << EOF
o
n
p
1

+${bootsize}MB
t
0c
n
p
2

+${swapsize}MB
t
2
82
n
p
3


t
3
83
p
w
EOF


mkdir -p $bootmount
mkdir -p $rootmount

umount $bootmount
umount $rootmount

#determine the block offsets of each partition

bootoffset=`parted $outname --script -- unit B print | grep primary | tr -s " " ":" | cut -d ":" -f 3 | sed s/B//g | head -n1`
bootsize=`parted $outname --script -- unit B print | grep primary | tr -s " " ":" | cut -d ":" -f 5 | sed s/B//g | head -n1`

swapoffset=`parted $outname --script -- unit B print | grep primary | tr -s " " ":" | cut -d ":" -f 3 | sed s/B//g | head -n2 | tail -n1`
swapsize=`parted $outname --script -- unit B print | grep primary | tr -s " " ":" | cut -d ":" -f 5 | sed s/B//g | head -n2 | tail -n1`


rootoffset=`parted $outname --script -- unit B print | grep primary | tr -s " " ":" | cut -d ":" -f 3 | sed s/B//g | tail -n1`
rootsize=`parted $outname --script -- unit B print | grep primary | tr -s " " ":" | cut -d ":" -f 5 | sed s/B//g | tail -n1`

echo $bootoffset $bootsize
echo $swapoffset $swapsize
echo $rootoffset $rootsize

#mount the loopback devices we created

bootloop=`losetup -f`
losetup --offset $bootoffset --sizelimit $bootsize $bootloop $outname 
mkdosfs -F 16 $bootloop


mount $bootloop $bootmount

swaploop=`losetup -f`
losetup --offset $swapoffset --sizelimit $swapsize $swaploop $outname 
mkswap $swaploop


rootloop=`losetup -f`
losetup --offset $rootoffset --sizelimit $rootsize $rootloop $outname 
mkfs.ext4 -i 8192 $rootloop # we need a larger number of inodes 

mount $rootloop $rootmount

df -h

losetup -d $swaploop


# setup the boot directory
cp -r $firmwaredir/boot/* $bootmount

cat << EOF > $bootmount/cmdline.txt
dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p3 rootfstype=ext4 elevator=deadline rootwait
EOF

#enable overclocking
cat << EOF > $bootmount/config.txt
arm_freq=900
core_freq=450
sdram_freq=450
force_turbo=1
disable_overscan=1
hdmi_force_hotplug=1
hdmi_drive=2
gpu_mem=100

#hdmi_force_edid_audio=1
EOF

#unmonut cleanup the boot directory
umount $bootmount
losetup -d $bootloop

#Extract the stage4 to the root mount
echo "Extracting stage4 into root..."
tar -C $rootmount -xpjf $payloadarch 
echo "Extraction complete"

echo "Copying portage profile"
cp -r ${payload}/usr/portage/profiles ${rootmount}/usr/portage/
cp -r ${payload}/usr/portage/eclass ${rootmount}/usr/portage
ls -l ${rootmount}/usr/portage/

umount $rootmount
losetup -d $rootloop

echo "Zipping up for distribution..."

time zip -r ${outname}.zip $outname

echo "Uploading $version to EC2"
time cp -v ${outname}.zip  $s3dir

