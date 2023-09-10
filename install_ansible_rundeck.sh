#!/bin/bash

# this script installs ansible and rundeck on a
# vanilla debian 11
# RUN AS ROOT!

# you might wan to change this
# sets all passwords of users and the vscode server to "onemarcfifty"

USERPASSWORD=onemarcfifty


# first we install some software

apt update
apt -y upgrade
apt install -y python3-full pip sudo wget curl git nmap

# now let's add the rundeck user

useradd -m -G sudo -s /bin/bash rundeck
echo "rundeck:$USERPASSWORD" | chpasswd

# Quick fix: allow sudo to the rundeck user without password
# (needs review) 

echo "rundeck  ALL=(ALL)  NOPASSWD: ALL" >/etc/sudoers.d/rundeck 

# install ansible through pip
sudo su - rundeck <<'EOF' 
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install ansible
python3 -m pip install requests
python3 -m pip install proxmoxer
EOF

# download the rundeck installation script and run it directly
# then install rundeck

curl https://raw.githubusercontent.com/rundeck/packaging/main/scripts/deb-setup.sh 2> /dev/null | sudo bash -s rundeck
apt update
apt -y install rundeck

# replace the localhost entries in the config files with the hostname
sed -i s/admin:admin/admin:$USERPASSWORD/g /etc/rundeck/realm.properties
sed -i s/localhost/`hostname`/g /etc/rundeck/framework.properties
sed -i s/localhost/`hostname`/g /etc/rundeck/rundeck-config.properties

# install mariadb
apt install -y mariadb-server
# create rundeck db
mysql -u root -e 'create database rundeck'
# create user, random pass and grant access
RANDOMPASSWORD=`date +%s | sha256sum | base64 | head -c 32`
mysql -u root -e "create user rundeck@localhost identified by '$RANDOMPASSWORD'"
mysql -u root -e 'grant ALL on rundeck.* to rundeck@localhost'

# update the rundeck config
# comment out the original data source

sed -i s/^dataSource.url/\#dataSource.url/g /etc/rundeck/rundeck-config.properties

# point the datasource to the new local mariadb installation

(cat >> /etc/rundeck/rundeck-config.properties) <<EOF
dataSource.driverClassName = org.mariadb.jdbc.Driver
dataSource.url = jdbc:mysql://localhost/rundeck?autoReconnect=true&useSSL=false
dataSource.username = rundeck
dataSource.password = $RANDOMPASSWORD
EOF
RANDOMPASSWORD="nothing here"

# start rundeck services

/etc/init.d/rundeckd start
systemctl enable rundeckd

# install ansible through pipx
#sudo su - rundeck -c "cat > /var/lib/rundeck/install-ansible.sh << 'EOF' 
#pipx install --include-deps ansible
#pipx inject ansible argcomplete
#pipx inject --include-apps ansible argcomplete
#pipx ensurepath
#EOF"
#sudo su - rundeck -c "chmod 755 install-ansible.sh"
#sudo su - rundeck -c "./install-ansible.sh"
#sudo su - rundeck -c "rm install-ansible.sh"

# now let's install visual studio code server (vscode-server)

wget https://github.com/coder/code-server/releases/download/v4.16.1/code-server_4.16.1_amd64.deb
sudo apt install ./code-server_4.16.1_amd64.deb

# now we need to configure a systemd unit file so that
# code-server starts automatically
# please note that this uses http unencrypted.
# You might want to tweak this for added security

(cat >/etc/systemd/system/code-server.service) <<EOF
[Unit]
Description=code-server
After=networking.service

[Service]
Type=simple
User=rundeck
Environment=PASSWORD=$USERPASSWORD
WorkingDirectory=/var/lib/rundeck
ExecStart=/usr/bin/code-server --host 0.0.0.0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable code-server.service
systemctl start code-server.service
