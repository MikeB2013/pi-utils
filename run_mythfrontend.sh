#!/bin/bash

# script to run mythfrontend from version 31 on Raspberry Pi under Raspian Buster using EGLFS
# can be added to .bashrc to allow autostart of mythfrontend on boot

# Last Modified 24 July 2020

# Author Mike Bibbings

# check if running via SSH, if so skip running mythfrontend, it must only run locally.
SSH=$(printenv | grep SSH_CLIENT)
if [ -n "$SSH" ]; then
#    echo "run_mythfrontend.sh cannot be run over ssh"
    exit 1
fi

#check mythfrontend has been installed, if not abort with message
MYTHFRONTEND=`which mythfrontend`
if [ -z "$MYTHFRONTEND" ]; then
    echo -e "mythfrontend not found - please install MythTV-Light package"
    echo -e "See 'https://www.mythtv.org/wiki/MythTV_Light'\n"
    exit 1
fi

#check for any arguments on command line, if so use for mythfrontend command, so we can use different parameters
#e.g. run_mythfrontend.sh --logpath /home/pi --loglevel debug
# if no arguments set --logpath /tmp
if [ -z "$*" ] ; then
	ARGUMENTS="--logpath /tmp"
else
	ARGUMENTS="$*"
fi

# do some basic checks
# check for drm, if not found abort with message
PI_DRM=$(grep -ic 'drm' /proc/modules)
if [ $PI_DRM = 0 ] ; then
	echo "Basic configuration check failed."
	echo "Please run 'sudo raspi-config' to set up:"
	echo "  G2 GL (Fake KMS) Open GL Desktop driver"
	echo "Also check that :"
	echo "  Wait for Network at boot  is enabled"
	echo "  Console AutoLogin is enabled"
	exit 2
fi
echo "Starting MythTV Frontend -- this may take a few seconds -- Please wait"

PI_MODEL=$(grep -ic 'Pi 4' /proc/device-tree/model)
# set perfomance mode, not sure if needed for Pi4, do it anyway
echo performance | sudo tee /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# try to fix issue with unable to allocate cma, pi model 2/3
# see https://www.raspberrypi.org/forums/viewtopic.php?f=53&t=223363&p=1613246&hilit=vc4_v3d+3fc00000.v3d%3A+Failed+to+allocate+memory+for+tile+binning%3A#p1613246
if [ $PI_MODEL = 0 ] ; then
    echo on | sudo tee /sys/devices/platform/soc/*.v3d/power/control
fi

#TODO check /boot/config for hdmi_group and hdmi_mode settings
#HDMI_MODE=$(grep '^hdmi_mode' /boot/config.txt)
#HDMI_GROUP=$(grep '^hdmi_group' /boot/config.txt)

# use tvservice -s for current settings.
# assumes User has setup required resolution.
# for resolutions greater than 1920x1080@60Hz
# hdmi_enable_4kp60=1 is required in /boot/config.txt for Pi4 (not applicable to Pi2/3)

CURRENT_REFRESH=$(tvservice -s|sed -n -e 's/^.*@ //p')
#get first 2 characters
CURRENT_REFRESH=${CURRENT_REFRESH:0:2}

CURRENT_RES=$(tvservice -s|sed -n -e 's/^.*], //p')
#strip out everything except resolution e.g. 1920x1080
CURRENT_RES=${CURRENT_RES%%[[:space:]]*}

RESOLUTION="$CURRENT_RES@$CURRENT_REFRESH"

echo "Setting screen to $RESOLUTION"

# we need override file to force correct resolution.
# QT defaults to using EDID from connected hdmi device
# pi2/3 use /dev/dri/card0,  pi4 /dev/dri/card1
# find out which model of Pi we have


if [ "$PI_MODEL" = 1 ]
then
      CARD="card1"
else
      CARD="card0"
fi

#file created everytime this script is run,avoids checking previous and current resolution everytime
bash -c "cat >/home/pi/pi_mythfrontend.json" <<ENDOFSCRIPTINPUT
{
    "device": "/dev/dri/${CARD}",
    "outputs": [
        { "name": "HDMI1", "mode": "${RESOLUTION}" }
    ]
}
ENDOFSCRIPTINPUT

#for QT debug add to command line QT_QPA_EGLFS_DEBUG=1 QT_LOGGING_RULES=qt.qpa.*=true
QT_QPA_EGLFS_ALWAYS_SET_MODE="1" QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_KMS_CONFIG=/home/pi/pi_mythfrontend.json mythfrontend $ARGUMENTS
# fixup keyboard after exit from mythfrontend, bug in QT causes segment fault which kills keyboard input
kbd_mode -u
# restore cursor
setterm  --cursor on

exit 0
