#!/bin/bash

set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

CONFIGDIR=/ops/shared/config

CONSULCONFIGDIR=/etc/consul.d
VAULTCONFIGDIR=/etc/vault.d
NOMADCONFIGDIR=/etc/nomad.d
CONSULTEMPLATECONFIGDIR=/etc/consul-template.d
HOME_DIR=ubuntu
AWS_DATA_IP=169.254.169.254


# Wait for network
sleep 15

DOCKER_BRIDGE_IP_ADDRESS=(`ifconfig docker0 2>/dev/null | awk '/inet / {print $2}'`)

SERVER_COUNT="${server_count}"
RETRY_JOIN="${retry_join}"

# Get IP from metadata service
IP_ADDRESS=$(curl http://$AWS_DATA_IP/latest/meta-data/local-ipv4)


# Consul
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/consul.hcl
sed -i "s/SERVER_COUNT/$SERVER_COUNT/g" $CONFIGDIR/consul.hcl
sed -i "s/RETRY_JOIN/$RETRY_JOIN/g" $CONFIGDIR/consul.hcl
cp $CONFIGDIR/consul.hcl $CONSULCONFIGDIR
cp $CONFIGDIR/consul_aws.service /etc/systemd/system/consul.service

systemctl enable consul.service
systemctl start consul.service
sleep 10
export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500
export CONSUL_RPC_ADDR=$IP_ADDRESS:8400


# Vault
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/vault.hcl
cp $CONFIGDIR/vault.hcl $VAULTCONFIGDIR
cp $CONFIGDIR/vault.service /etc/systemd/system/vault.service

systemctl enable vault.service
systemctl start vault.service


# Nomad

## Replace existing Nomad binary if remote file exists
if [[ `wget -S --spider $NOMAD_BINARY  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
  curl -L $NOMAD_BINARY > nomad.zip
  unzip -o nomad.zip -d /usr/local/bin
  chmod 0755 /usr/local/bin/nomad
  chown root:root /usr/local/bin/nomad
fi

sed -i "s/SERVER_COUNT/$SERVER_COUNT/g" $CONFIGDIR/nomad.hcl
cp $CONFIGDIR/nomad.hcl $NOMADCONFIGDIR
cp $CONFIGDIR/nomad.service /etc/systemd/system/nomad.service

systemctl enable nomad.service
systemctl start nomad.service
sleep 10
export NOMAD_ADDR=http://$IP_ADDRESS:4646


# Consul Template
cp $CONFIGDIR/consul-template.hcl $CONSULTEMPLATECONFIGDIR/consul-template.hcl
cp $CONFIGDIR/consul-template.service /etc/systemd/system/consul-template.service


# Add hostname to /etc/hosts
echo "127.0.0.1 $(hostname)" | tee --append /etc/hosts


# Add Docker bridge network IP and AWS DNS to /etc/resolv.conf (at the top)
echo "nameserver $DOCKER_BRIDGE_IP_ADDRESS" | tee /etc/resolv.conf.new
echo "nameserver 169.254.169.253" | tee -a /etc/resolv.conf.new
cat /etc/resolv.conf | tee --append /etc/resolv.conf.new
mv /etc/resolv.conf.new /etc/resolv.conf


# Set env vars for tool CLIs
echo "export CONSUL_RPC_ADDR=$IP_ADDRESS:8400" | tee --append /home/$HOME_DIR/.bashrc
echo "export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500" | tee --append /home/$HOME_DIR/.bashrc
echo "export VAULT_ADDR=http://$IP_ADDRESS:8200" | tee --append /home/$HOME_DIR/.bashrc
echo "export NOMAD_ADDR=http://$IP_ADDRESS:4646" | tee --append /home/$HOME_DIR/.bashrc
