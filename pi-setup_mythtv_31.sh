#!/bin/bash

# Last Modified 20 June 2020

# fixed mythpluguns-light install
# Script to setup MythTV 31 for Raspberry Pi under Raspbian Buster
# runs from console using eglfs for best performance.
# very little error checking

#The script does the following:
# sets apt repository for mythtv-light fixes/31
# installs mythtv-light
# default sets Raspberry Pi configuration, boot to console, wait for network, use vc4-fkms driver, ssh enabled, gpu_mem=256.
# Options to install mythplugins, disable ssh,install scripts for mythbackend (run seperately).

# Author Mike Bibbings

# Globals

#mythtv-light version
MYTHTV_LIGHT_VERSION="deb http://dl.bintray.com/bennettpeter/deb/ buster myth31"
MYTHTV_LIGHT_KEY="https://bintray.com/user/downloadSubjectPublicKey?username=bintray"
MYTITLE="MythTV Setup for Raspberry Pi"

# my pi-utils repository
PI_UTILS_REPO="https://github.com/MikeB2013/pi-utils.git"

# for whiptail items 0=Yes, 1=No -1=error (not currently checked)
DEFAULT_INSTALL=0
MYTHPLUGINS=1
RUNCONSOLE=0
AUTOSTART=0
MYTHBACKEND=1
PERFORMANCE=1
ENABLESSH=0
GET_SD_EXTERNAL_HELPER=1
WAITNETWORK=0
GPU_MEM=256
OS_CHECK="10 (buster)"
REBOOT=0

# functions

do_get_setup_required()
{
whiptail --title "$MYTITLE" --yesno "Default Install of MythTV Frontend\nThe following will be setup:\nMythTV Frontend\nRun from Console\nWait for network\nSSH Enabled\nAuto start at boot\nGPU_MEM=$GPU_MEM\nOverclock (Pi2 only)\n\nSelect No for individual options, including mythbackend, mythplugins-light\n\nNote: Internet Access is required." 20 50
DEFAULT_INSTALL=$?

if [ $DEFAULT_INSTALL = 1 ] ; then
    whiptail --title "$MYTITLE" --yesno "Install mythplugins" 10 50
    MYTHPLUGINS=$?

    whiptail --title "$MYTITLE" --yesno "Auto start mythfrontend" 10 50
    AUTOSTART=$?

    whiptail --title "$MYTITLE" --yesno --defaultno "Install mythbackend scripts\nRun scripts manually\npi-mythbackend-helper.sh installs additional items for mythbackend\npi-SDtoHD-helper.sh moves rootfs to external disk\nrun_mythsetup.sh is for mythtv-setup" 20 50
    MYTHBACKEND=$?

    whiptail --title "$MYTITLE" --yesno "Enable SSH" 10 50
    ENABLESSH=$?

fi
}

do_mythbackend()
{
# uses scripts from my repo
if [ $MYTHBACKEND = 0 ] ; then
    cp $HOME/pi-utils/pi-mythbackend-helper.sh $HOME
    cp $HOME/pi-utils/pi-SDtoHD-helper.sh $HOME
    cp $HOME/pi-utils/run_mythsetup.sh $HOME
fi
}

do_finish()
{
if [ $MYTHBACKEND = 0 ] ; then
    echo -e "\n\nTo install mythtv backend components run script 'pi-mythbackend-helper.sh'\n\nTo move rootfs run script 'pi-SDtoHD-helper.sh'\n\nTo run mythtv-setup use script 'run_mythsetup.sh'\n\nscripts are in '/home/pi/'\n\n"
fi

if [ $AUTOSTART = 0 ] ; then
	echo -e "\nAutostart mythfrontend at boot is enabled"
else
	echo -e "\nTo run mythfrontend type ./run_mythfrontend.sh at console prompt"
fi

if [ $ENABLESSH = 0 ] ; then
	echo -e "\nSSH access is enabled"
fi

echo -e "A reboot is required, please type sudo reboot\n"

}

do_install_mythtv_from_repo()
{
#setup sources.list
ALREADY_ADDED=$(grep -ic "$MYTHTV_LIGHT_VERSION" /etc/apt/sources.list)
#don't add more than once - it generates  apt warnings (harmless)
if [ $ALREADY_ADDED = 0 ] ; then
	echo "$MYTHTV_LIGHT_VERSION" | sudo tee -a /etc/apt/sources.list
	#setup bintray key
	wget -O - $MYTHTV_LIGHT_KEY | sudo apt-key add -
fi

# install mythtv-light
# first make sure we are upto date.
sudo apt update
sudo apt upgrade -y
sudo apt install git mythtv-light -y

if [ $MYTHPLUGINS = 0 ] ; then
    sudo apt install mythplugins-light -y
fi

# get all scripts from my github repository
cd $HOME
if [ ! -e $HOME/pi-utils ] ; then
	git clone $PI_UTILS_REPO
else
	# update repo
	cd $HOME/pi-utils
	git pull
	cd $HOME
fi

# performance govenor is setup in run_mythfrontend.sh
cp $HOME/pi-utils/run_mythfrontend.sh $HOME
chmod +x $HOME/run_mythfrontend.sh

if [ $ENABLESSH = 0 ] ; then
    sudo raspi-config nonint do_ssh 0
fi

if [ $RUNCONSOLE = 0 ] ; then
    sudo raspi-config nonint do_boot_behaviour B2      # Boot to CLI & auto login as pi user
fi

if [ $WAITNETWORK = 0 ] ; then
    sudo raspi-config nonint do_boot_wait 0
fi

# set overclock (only applies to Pi2)
if [ $PI_MODEL2 = 1 ] ; then
    sudo raspi-config nonint do_overclock High
fi

# set gpu_mem
sudo raspi-config nonint do_memory_split $GPU_MEM

# setup vc4-fkms-v3d
# extracted from raspi-config code, as vc4-fkms-v3d cannot be setup using nonint mode of raspi-config
CONFIG=/boot/config.txt
sudo sed $CONFIG -i -e "s/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/g"
sudo sed $CONFIG -i -e "s/^#dtoverlay=vc4-fkms-v3d/dtoverlay=vc4-fkms-v3d/g"
if ! sed -n "/\[pi4\]/,/\[/ !p" $CONFIG | grep -q "^dtoverlay=vc4-fkms-v3d" ; then
    sudo printf "[all]\ndtoverlay=vc4-fkms-v3d\n" >> $CONFIG
fi

if [ $AUTOSTART = 0 ] ; then
    if [ -e $HOME/.bashrc ] ; then
        #check if run_mythfrontend.sh exists in .bashrc
        RUN=$(grep -ic "run_mythfrontend.sh" .bashrc)
        if [ $RUN = 0 ] ; then
            # add to bash.rc
            echo "$HOME/run_mythfrontend.sh" >> .bashrc
        fi
    fi
fi

}

do_cleanup()
{
# remove pi-utils
rm -fr $HOME/pi-utils
}


# main
#check operating system is buster
RUNNING_OS=$(grep -ic "${OS_CHECK}" /etc/os-release)
if [ $RUNNING_OS -ne 2 ] ; then
    echo "Required Operating System Raspbian $OS_CHECK not found , exiting"
    echo "Raspbian is available at 'https://www.raspberrypi.org/downloads/raspbian/'"
    exit 1
fi

#check for Pi 4
PI_MODEL4=$(grep -ics 'Pi 4' /proc/device-tree/model)

#check for Pi 2
PI_MODEL2=$(grep -ics 'Pi 2' /proc/device-tree/model)

#check for Pi 3
PI_MODEL3=$(grep -ics 'Pi 3' /proc/device-tree/model)
#echo "pi2 = $PI_MODEL2 pi3 = $PI_MODEL3 pi4 = $PI_MODEL4"
# if not pi2, pi3 or pi4 then exit

if [ "$PI_MODEL2" = 0  ] && [ "$PI_MODEL3" = 0 ] && [ "$PI_MODEL4" = 0 ] ; then
    echo "This script only works for Pi Models 2,3 and 4"
    exit 1
fi

do_get_setup_required
do_install_mythtv_from_repo
do_mythbackend
do_cleanup
do_finish

exit 0


