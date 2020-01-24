#! /bin/bash

# Last Modified 21 August 2019
# use /tmp/build for mythtv_git_directory
# fixed mythtv-database daily backup

# Author Mike Bibbings

# helper script to setup mythtv-backend on Raspberry pi 4

# Aborts if MythTV-Light package has not been installed
# This script setups the following:
# Installs mariadb-server, creates mythconverg database and sets daily backup.
# Installs mythweb
# setups mythtv user for running mythbackend
# setups various directories on the file system for recordings etc. uses /srv/mythtv
# setup logging with rotation
# setup systemd mythtv-backend.service file
# Install xmltv for external program data e.g. Schedules Direct with tvgrab_zz_sdjson

# script is stuctured as series of function calls (fn_xxx), allowing easier customisation.
# to disable a fn_xxx call just put # at start of line, the calls are near the end of this script.

# todo
# if mythtv_password is not 'mythtv' edit mythweb.conf accordingly


#Notes for this script
# Script is only intended as a stop gap, if/until full packaged builds are available
# There is very little error checking/handling in this script
# Script is intentionally verbose.
# Script is intended to run once, but can be run multiple times, but some errors will be seen, not harmfull.
# Where files are edited a backup copy is made on first run, <filename> with .original appended.
# The backup copy is protected as use is made of -n (noclobber) in cp command on running this script.

# Globals
mythtv_git_directory=/tmp/build
mythtv_git_branch=master   # just use master, it is ok to use this for mythtv 30
mythtv_password=mythtv    #if changed need to manually update /etc/apache2/sites-available/mythweb.conf
mythtv_storagegroup_path=/srv/mythtv/ # using /srv/mythtv in preference to /var/lib/mythtv/,
mythtv_storagegroups="banners coverart fanart recordings streaming videos bare-client db_backups  livetv  screenshots  trailers music musicart"
php_version="7.3" # this is to allow for easy change
mythweb_max_input_vars=30000 # this increases number of channels to around  1800 over all videosources

# this gets git source for mythweb and mythtv/packaging
fn_get_git()
{

mkdir -p $mythtv_git_directory
cd $mythtv_git_directory
#mythweb
git clone -b $mythtv_git_branch --depth 1 https://github.com/MythTV/mythweb.git mythweb
#mythtv packaging - we only need a few files
git clone -b $mythtv_git_branch --depth 1 https://github.com/MythTV/packaging.git
}


fn_setup_mythtv_user()
{
sudo useradd --system mythtv --groups cdrom,audio,video
# allow default user, usually pi to run mythtv-setup
sudo adduser $USER mythtv

# create basic config.xml in /etc/mythtv/ same as ubuntu (mythbuntu ppa)/debian (built from source)
sudo mkdir -p /etc/mythtv/

sudo bash -c "cat >/etc/mythtv/config.xml" <<ENDOFSCRIPTINPUT
<Configuration>
  <LocalHostName>my-unique-identifier-goes-here</LocalHostName>
  <Database>
    <PingHost>1</PingHost>
    <Host>localhost</Host>
    <UserName>mythtv</UserName>
    <Password>${mythtv_password}</Password>
    <DatabaseName>mythconverg</DatabaseName>
    <Port>3306</Port>
  </Database>
  <WakeOnLAN>
    <Enabled>0</Enabled>
    <SQLReconnectWaitTime>0</SQLReconnectWaitTime>
    <SQLConnectRetry>5</SQLConnectRetry>
    <Command>echo 'WOLsqlServerCommand not set'</Command>
  </WakeOnLAN>
</Configuration>

ENDOFSCRIPTINPUT

sudo mkdir -p /home/mythtv/.mythtv/   # for mythtv user
sudo ln -s /etc/mythtv/config.xml /home/mythtv/.mythtv/config.xml
sudo cp $mythtv_git_directory/packaging/deb/debian/session-settings /etc/mythtv/
sudo chown -R mythtv:mythtv /home/mythtv/ /etc/mythtv

mkdir -p $HOME/.mythtv/  # for pi user
ln -s /etc/mythtv/config.xml $HOME/.mythtv/config.xml # for mythfrontend

sudo cp $mythtv_git_directory/packaging/deb/debian/41-mythtv-permissions.rules /lib/udev/rules.d/
sudo cp $mythtv_git_directory/packaging/deb/debian/30-mythtv-sysctl.conf /etc/sysctl.d/

}

fn_setup_xmltv()
{
sudo apt install xmltv -y
echo -e "\nxmltv has been installed"

}

fn_setup_mariadb()
{
sudo apt install mariadb-server -y
#setup timezone info
mysql_tzinfo_to_sql /usr/share/zoneinfo | sudo mysql -uroot mysql
# todo really should secure mariadb

sudo systemctl restart mysql

#setup mythconverg db
sudo mysql -uroot << ENDOFSCRIPTINPUT

CREATE DATABASE IF NOT EXISTS mythconverg;
CREATE USER IF NOT EXISTS 'mythtv'@'%' IDENTIFIED BY 'mythtv';
CREATE USER IF NOT EXISTS 'mythtv'@'localhost' IDENTIFIED BY 'mythtv';
SET PASSWORD FOR 'mythtv'@'%' = PASSWORD('$mythtv_password');
SET PASSWORD FOR 'mythtv'@'localhost' = PASSWORD('$mythtv_password');
CONNECT mythconverg;
GRANT ALL PRIVILEGES ON *.* TO 'mythtv'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'mythtv'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT
ENDOFSCRIPTINPUT

# mythtv.cnf for mariadb
sudo cp $mythtv_git_directory/packaging/deb/debian/mythtv.cnf /etc/mysql/mariadb.conf.d/
echo -e "\nmythconverg database created for user mythtv - password $mythtv_password"

}

fn_mythconverg_daily_backup()
{
# setup mythconverg daily backup, instead of weekly (personal preference)
sudo cp $mythtv_git_directory/packaging/deb/debian/mythtv-database.cron.weekly /etc/cron.daily/mythtv-database
sudo chmod +x /etc/cron.daily/mythtv-database
# the following is not necessary for mythtv master, only for previous versions e.g. 29 or 30
# it does no harm with mythtv master and is only required for mythconverg db backups
# The version of mythtv-database.cron.weekly in mythtv packaging/master has a change to force user mythtv
#sudo mkdir -p /root/.mythtv/
#sudo ln -s /etc/mythtv/config.xml /root/.mythtv/config.xml
echo -e "daily backup of mythconverg database has been setup"

}

fn_install_mythweb()
{

sudo apt install apache2 php php-mysql -y
# installs php 7.3 on Raspbian Buster
# mythtv-light uses /usr/ not /usr/local/
sudo cp -r $mythtv_git_directory/mythweb /usr/share/mythtv/mythweb
sudo ln -s /usr/share/mythtv/mythweb/ /var/www/html/
sudo cp -v /usr/share/mythtv/mythweb/mythweb.conf.apache /etc/apache2/sites-available/mythweb.conf

#todo check if file exists, if so skip with message, user may have changed it, for now use -n (noclobber)
sudo cp -n $mythtv_git_directory/packaging/deb/debian/20-mythweb.ini /etc/php/$php_version/apache2/conf.d/
# if lots of channels e.g. satellite you might need to change file 20-mythweb.ini in /etc/php/7.3/apache2/conf.d with contents
# default are 10000 input vars, at 16 vars per channel that is 620 channels
#e.g. max_input_vars = 30000

#for safety make a copy.
sudo cp -n /etc/apache2/sites-available/mythweb.conf /etc/apache2/sites-available/mythweb.conf.orignal

sudo sed -i -e 's|"/var/www/html|"/var/www/html/mythweb|g' /etc/apache2/sites-available/mythweb.conf
sudo sed -i -e 's|#    setenv db_server|setenv db_server|g' /etc/apache2/sites-available/mythweb.conf
sudo sed -i -e 's|#    setenv db_name|setenv db_name|g' /etc/apache2/sites-available/mythweb.conf
sudo sed -i -e 's|#    setenv db_login|setenv db_login|g' /etc/apache2/sites-available/mythweb.conf
sudo sed -i -e 's|#    setenv db_password|setenv db_password|g' /etc/apache2/sites-available/mythweb.conf

#setup apache2
sudo a2enmod rewrite
sudo a2enmod cgi
sudo a2ensite mythweb.conf
sudo chown -R www-data:www-data /usr/share/mythtv/mythweb/data/
sudo chmod -R g+w /usr/share/mythtv/mythweb/data/
sudo systemctl restart apache2.service
echo -e "\nmythweb has been installed.\n"

}

fn_setup_directories()
{
sudo mkdir -p $mythtv_storagegroup_path
cd $mythtv_storagegroup_path
sudo mkdir -p $mythtv_storagegroups
sudo chown -R mythtv:mythtv $mythtv_storagegroup_path
sudo chmod -R  2775 $mythtv_storagegroup_path

}

fn_setup_mythtv_backend_service()
{
#todo check if already exists and skip if it does with message, user may have modified it
# user should have created ovdrride file instead of modifying directly
# for now use -n (noclobber)

sudo cp -n $mythtv_git_directory/packaging/deb/debian/mythtv-backend.service /lib/systemd/system/
sudo systemctl enable mythtv-backend
sudo systemctl daemon-reload
echo -e "\nmythtv-backend.service has been setup and enabled \n"

}

fn_setup_logging()
{
sudo cp $mythtv_git_directory/packaging/deb/debian/40-mythtv.conf /etc/rsyslog.d/
sudo cp $mythtv_git_directory/packaging/deb/debian/mythtv-backend.logrotate /etc/logrotate.d/mythtv-backend
sudo cp $mythtv_git_directory/packaging/deb/debian/mythtv-common.logrotate /etc/logrotate.d/mythtv-common
sudo cp $mythtv_git_directory/packaging/deb/debian/mythtv-frontend.logrotate /etc/logrotate.d/mythtv-frontend
sudo cp $mythtv_git_directory/packaging/deb/debian/mythtv-transcode-utils.logrotate /etc/logrotate.d/mythtv-transcode-utils
echo -e "\nmythtv log rotation has been setup \n"

}

# increase max_vars for mythweb needed for more than 620 channels over all videosources.
fn_mythweb_increase_max_vars()
{
# backup the file before editing
sudo cp -n /etc/php/$php_version/apache2/conf.d/20-mythweb.ini /etc/php/$php_version/apache2/conf.d/20-mythweb.ini.original
sudo sed -i -e "s|10000|${mythweb_max_input_vars}|g" /etc/php/$php_version/apache2/conf.d/20-mythweb.ini
}

#allows remote connections from other mythtv frontends
fn_enable_remote_frontends()
{
# backup file
sudo cp -n /etc/mysql/mariadb.conf.d/mythtv.cnf /etc/mysql/mariadb.conf.d/mythtv.cnf.original
sudo sed -i -e 's|#bind-address|bind-address|g' /etc/mysql/mariadb.conf.d/mythtv.cnf
}

fn_tidy_up()
{
# remove local packaging and mythweb git repositories
rm -fr  $mythtv_git_directory/mythweb
rm -fr  $mythtv_git_directory/packaging
}

#main

#check mythbackend has been installed, if not abort with message
MYTHBACKEND=`which mythbackend`
if [ -z "$MYTHBACKEND" ]; then
    echo -e "mythbackend not found - please install MythTV-Light package"
    echo -e "For official builds (when available) 'https://www.mythtv.org/wiki/MythTV_Light'\n"
    echo -e "For test builds 'https://forum.mythtv.org/viewtopic.php?f=46&t=3221&start=15'\n"
    exit 1
fi

# make sure all packages are upto date
sudo apt update && sudo apt upgrade -y

# make sure we have git, Raspbian Buster Lite image does not
sudo apt install git -y

#needed for optimize_mythdb.pl (fixed in packaging master)
sudo apt install libio-socket-inet6-perl -y

# to disable any fn_ call just put # in front
# change the order at own risk - not tested!
fn_get_git
fn_setup_mythtv_user
fn_setup_mariadb
fn_mythconverg_daily_backup
fn_install_mythweb
fn_setup_mythtv_backend_service
fn_setup_xmltv
fn_setup_logging
fn_setup_directories
fn_mythweb_increase_max_vars
fn_enable_remote_frontends
fn_mythconverg_daily_backup
fn_tidy_up


echo -e "\n**************************************************"

echo -e "\nIf running headless on Pi4, no monitor connected on hdmi port"
echo -e " put 'hdmi_ignore_cec=1' in '/boot/config.txt' and reboot"
echo -e "\nStorage Group directories have been created in '$mythtv_storagegroup_path'"
echo -e "Directories '$mythtv_storagegroups'"
echo -e "Use mythtv-setup Storage Directories to setup those required"
echo -e "\nUse systemctl commands to stop or start mythtv-backend"
echo -e "  To stop  'sudo systemctl stop mythtv-backend'"
echo -e "  To start 'sudo systemctl start mythtv-backend'"
echo -e "  Sometimes mythtv-backend maybe 'failed' by systemd, to re-enable use"
echo -e "   'sudo systemctl daemon-reload' followed by"
echo -e "   'sudo systemctl start mythtv-backend'"
echo -e "\nWhen using xmltv e.g. tv_grab_zz_sdjson"
echo -e "mythfilldatabase arguments should use '--no-allatonce'"
echo -e "\nmythconverg database password '$mythtv_password'"
echo -e "\nReferences:"
echo -e "  https://www.mythtv.org/wiki/MythTV_Light"
echo -e "  https://www.mythtv.org/wiki/Database_Setup"
echo -e "  https://www.mythtv.org/wiki/Build_from_Source"
echo -e "  https://www.mythtv.org/wiki/Systemd_mythbackend_Configuration"
echo -e "  https://www.mythtv.org/wiki/Setup_Storage_Directories"
echo -e "  https://www.mythtv.org/wiki/Mythfilldatabase"
echo -e "\nFinished setting up for mythtv-backend - Please reboot\n"
exit 0


