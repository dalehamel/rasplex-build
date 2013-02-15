mount -t proc none /rpi/proc
mount --rbind /dev /rpi/dev
mount --rbind /sys /rpi/sys
mount --rbind /dev/pts /rpi/dev/pts

echo "Entering chroot"
chroot /rpi
echo "Leaving chroot"

umount  -l /rpi/proc
umount  -l /rpi/sys
umount  -l /rpi/dev/pts
umount  -l /rpi/dev/shm
umount  -l /rpi/dev
