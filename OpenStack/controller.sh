#!/bin/bash
###########################################################################
##       ffff55555                                                       ##
##     ffffffff555555                                                    ##
##   fff      f5    55         Deployment Script Version 0.0.1           ##
##  ff    fffff     555                                                  ##
##  ff    fffff f555555                                                  ##
## fff       f  f5555555             Written By: EIS Consulting          ##
## f        ff  f5555555                                                 ##
## fff   ffff       f555             Date Created: 05/05/2016            ##
## fff    fff5555    555             Last Updated: 05/06/2016            ##
##  ff    fff 55555  55                                                  ##
##   f    fff  555   5       This script will finish setting up a full   ##
##   f    fff       55       OpenStack Controller                        ##
##    ffffffff5555555                                                    ##
##       fffffff55                                                       ##
###########################################################################
###########################################################################
##                              Change Log                               ##
###########################################################################
## Version #     Name       #                    NOTES                   ##
###########################################################################
## 05/05/16#  Thomas Stanley#    Created base functionality              ##
## 05/06/16#  Thomas Stanley#    Still creating base functionality       ##
###########################################################################

## Variables Section
## $1 = openstack password

apt-get -y update
apt-get -y dist-upgrade

apt-get -y install build-essential libssl-dev binutils binutils-dev openssl
apt-get -y install libdb-dev libexpat1-dev automake checkinstall unzip elinks sshpass

## Install and Configure NTP Service
apt-get -y install chrony
sed -i 's|pool 2.debian.pool.ntp.org offline iburst|server 0.north-america.pool.ntp.org iburst|' /etc/chrony/chrony.conf
service chrony restart

## Install the OpenStack Packages
add-apt-repository -y cloud-archive:mitaka
apt-get -y update
apt-get -y dist-upgrade
apt-get -y install python-openstackclient

## Install and configure Mariadb Server
apt-get -y install mariadb-server python-pymysql
myip=$(ip route get 1 | awk '{print $NF;exit}')
echo "[mysqld]" >> /etc/mysql/conf.d/openstack.cnf
echo "bind-address = $myip" >> /etc/mysql/conf.d/openstack.cnf
echo "default-storage-engine = innodb" >> /etc/mysql/conf.d/openstack.cnf
echo "innodb_file_per_table" >> /etc/mysql/conf.d/openstack.cnf
echo "collation-server = utf8_general_ci" >> /etc/mysql/conf.d/openstack.cnf
echo "character-set-server = utf8" >> /etc/mysql/conf.d/openstack.cnf
sed -i "s|character-set-server  = utf8mb4|character-set-server  = utf8|" /etc/mysql/mariadb.conf.d/50-server.cnf
sed -i "s|collation-server      = utf8mb4_general_ci|collation-server      = utf8_general_ci|" /etc/mysql/mariadb.conf.d/50-server.cnf
sed -i "s|default-character-set = utf8mb4|default-character-set = utf8|" /etc/mysql/mariadb.conf.d/50-client.cnf
sed -i "s|default-character-set = utf8mb4|default-character-set = utf8|" /etc/mysql/mariadb.conf.d/50-mysql-clients.cnf
service mysql restart
mysqladmin -u root password "$1"

## Install and configure NoSQL Database
apt-get -y install mongodb-server mongodb-clients python-pymongo
sed -i "s|bind_ip = 127.0.0.1|bind_ip = $myip|" /etc/mongodb.conf
service mongodb start

## Install the Message Queue
apt-get -y install rabbitmq-server
rabbitmqctl add_user openstack "$1"
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

## Install and configure Memcached
apt-get -y install memcached python-memcache
sed -i "s|-l 127.0.0.1|-l $myip|" /etc/memcached.conf
service memcached restart

## Install and configure the identity service
#### Prerequisites
mysql -u root -p"$1" -Bse 'CREATE DATABASE keystone;'
mysql -u root -p"$1" -Bse "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$1';"
mysql -u root -p"$1" -Bse "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$1';"

#### Installation and Configuration
echo "manual" > /etc/init/keystone.override
apt-get -y install keystone apache2 libapache2-mod-wsgi
sed -i "s|#admin_token = <None>|admin_token = supersecrettoken|" /etc/keystone/keystone.conf
sed -i '/#connection = <None>/ a connection = mysql+pymysql://keystone:$1@controller/keystone' /etc/keystone/keystone.conf
sed -i "s|connection = sqlite:////var/lib/keystone/keystone.db|connection = mysql+pymysql://keystone:$1@localhost/keystone|" /etc/keystone/keystone.conf
sed -i "s|#provider = uuid|provider = fernet|" /etc/keystone/keystone.conf
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

#### Configure Apache2
echo "ServerName controller" >> /etc/apache2/apache2.conf
echo -e "Listen 5000" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "Listen 35357\n" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "<VirtualHost *:5000>" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIProcessGroup keystone-public" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIScriptAlias / /usr/bin/keystone-wsgi-public" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIApplicationGroup %{GLOBAL}" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIPassAuthorization On" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e '     ErrorLogFormat "%{cu}t %M"' >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     ErrorLog /var/log/apache2/keystone.log" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     CustomLog /var/log/apache2/keystone_access.log combined\n" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     <Directory /usr/bin>" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "          Require all granted" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     </Directory>" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "</VirtualHost>\n" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "<VirtualHost *:35357>" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIProcessGroup keystone-admin" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIScriptAlias / /usr/bin/keystone-wsgi-admin" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIApplicationGroup %{GLOBAL}" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     WSGIPassAuthorization On" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e '     ErrorLogFormat "%{cu}t %M"' >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     ErrorLog /var/log/apache2/keystone.log" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     CustomLog /var/log/apache2/keystone_access.log combined\n" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     <Directory /usr/bin>" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "          Require all granted" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "     </Directory>" >> /etc/apache2/sites-available/wsgi-keystone.conf
echo -e "</VirtualHost>\n" >> /etc/apache2/sites-available/wsgi-keystone.conf

#### Enable the Identity Service
ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
service apache2 restart
rm -f /var/lib/keystone/keystone.db

##Install and configure Service Entity and API Endpoints
export OS_TOKEN=supersecrettoken
export OS_URL=http://localhost:35357/v3
export OS_IDENTITY_API_VERSION=3
openstack service create --name keystone --description "OpenStack Identity" identity
openstack endpoint create --region RegionOne identity public http://localhost:5000/v3
openstack endpoint create --region RegionOne identity internal http://controller:5000/v3
openstack endpoint create --region RegionOne identity admin http://controller:35357/v3

## Create Admin and User, Domain, Role, and Projects
openstack domain create --description "Default Domain" default
openstack project create --domain default --description "Admin Project" admin
openstack user create --domain default --password "$1" admin
openstack role create admin
openstack role add --project admin --user admin admin
openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Demo Project" demo
openstack user create --domain default --password "$1" demo
openstack role create user
openstack role add --project demo --user demo user

## Create Environment Scripts
echo -e "export OS_PROJECT_DOMAIN_NAME=default"  >> ~/admin-openrc
echo -e "export OS_USER_DOMAIN_NAME=default"  >> ~/admin-openrc
echo -e "export OS_PROJECT_NAME=admin"  >> ~/admin-openrc
echo -e "export OS_USERNAME=admin"  >> ~/admin-openrc
echo -e "export OS_PASSWORD=$1"  >> ~/admin-openrc
echo -e "export OS_AUTH_URL=http://localhost:35357/v3"  >> ~/admin-openrc
echo -e "export OS_IDENTITY_API_VERSION=3"  >> ~/admin-openrc
echo -e "export OS_IMAGE_API_VERSION=2"  >> ~/admin-openrc
echo -e "export OS_PROJECT_DOMAIN_NAME=default"  >> ~/demo-openrc
echo -e "export OS_USER_DOMAIN_NAME=default"  >> ~/demo-openrc
echo -e "export OS_PROJECT_NAME=demo"  >> ~/demo-openrc
echo -e "export OS_USERNAME=demo"  >> ~/demo-openrc
echo -e "export OS_PASSWORD=$1"  >> ~/demo-openrc
echo -e "export OS_AUTH_URL=http://localhost:5000/v3"  >> ~/demo-openrc
echo -e "export OS_IDENTITY_API_VERSION=3"  >> ~/demo-openrc
echo -e "export OS_IMAGE_API_VERSION=2"  >> ~/demo-openrc
chmod +x ~/admin-openrc
chmod +x ~/demo-openrc

