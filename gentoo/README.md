# Overview of Setting up the gentoo build

The build consists of these basic steps

+ Setting up qemu-binfmt arm kernel emulation
+ Getting a stage3 to chroot into
+ Cloning the necessary repositories
+ Enabling distcc (optional but recommended)
+ running "emerge rasplex" which pulls in all dependencies


# About this guide

Wherever possible, scripts will be included to help automate the process. If something cannot be automated, it will be described as best as possble, to help reproduce the build process.
