#!/bin/bash

# script to run mythtv-setup from version 31 on Raspberry Pi under Raspian Buster using EGLFS

# Last Modified 24 July 2020

# Author Mike Bibbings

#check mythbackend is present, if not exit with message
MYTHBACKEND=`which mythbackend`
if [ -z "$MYTHBACKEND" ]; then
    echo -e "mythbackend not found - exiting"
    exit 1
fi

#check for any arguments on command line, if so use for mythtv-setup command, so we can use different parameters
#e.g. run_mythsetup.sh --logpath /home/pi --loglevel debug
echo "For different parameters to mythtv-setup, default is --logpath /tmp"
echo "$0 --logpath /home/pi/ --loglevel debug"
# if no arguments set --logpath /tmp
if [ -z "$*" ] ; then
	ARGUMENTS="--logpath /tmp"
else
	ARGUMENTS="$*"
fi
echo "arguments = $ARGUMENTS"

# check if running via SSH, if so just stop mythbackend, start mythtv-setup
SSH=$(printenv | grep SSH)
#echo "SSH Running = $SSH"
if [ -n "$SSH" ]; then
echo "Stopping mythbackend - this may take a few seconds"
sudo systemctl stop mythtv-backend
mythtv-setup $ARGUMENTS
echo "Starting mythbackend - this may take a few seconds"
sudo systemctl daemon-reload
sudo systemctl start mythtv-backend
exit 0
fi


echo "Starting MythTV Setup -- this may take a few seconds -- Please wait"

#stop mythtv-backend
echo "Stopping mythtv-backend - this may take a few seconds"
sudo systemctl stop mythtv-backend.service

#for QT debug add to command line QT_QPA_EGLFS_DEBUG=1 QT_LOGGING_RULES=qt.qpa.*=true 
#QT_QPA_EGLFS_DEBUG=1 QT_LOGGING_RULES=qt.qpa.*=true QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_KMS_CONFIG=/home/pi/pi_mythfrontend.json mythtv-setup --logpath /tmp  
QT_QPA_EGLFS_ALWAYS_SET_MODE="1" QT_QPA_PLATFORM=eglfs mythtv-setup $ARGUMENTS
# fixup keyboard after exit from mythfrontend (bug in QT causes segment fault which kills keyboard input)
kbd_mode -u
# restore cursor
setterm  --cursor on

#start mythtv-backend
echo "Restarting mythbackend - this may take a few seconds"
sudo systemctl daemon-reload
sudo systemctl start mythtv-backend

exit 0
