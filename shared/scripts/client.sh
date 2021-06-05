#!/bin/bash

set -e

CONFIGDIR=/ops/shared/config

CONSULCONFIGDIR=/etc/consul.d
NOMADCONFIGDIR=/etc/nomad.d
CONSULTEMPLATECONFIGDIR=/etc/consul-template.d
HOME_DIR=ubuntu
AWS_DATA_IP=169.254.169.254

# Wait for network
sleep 15

DOCKER_BRIDGE_IP_ADDRESS=(`ifconfig docker0 2>/dev/null | awk '/inet / {print $2}'`)
CLOUD=$1
RETRY_JOIN=$2
NOMAD_BINARY=$3

# Get IP from metadata service
IP_ADDRESS=$(curl http://$AWS_DATA_IP/latest/meta-data/local-ipv4)


# Consul
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/consul_client.hcl
sed -i "s/RETRY_JOIN/$RETRY_JOIN/g" $CONFIGDIR/consul_client.hcl
cp $CONFIGDIR/consul_client.hcl $CONSULCONFIGDIR/consul.hcl
cp $CONFIGDIR/consul_$CLOUD.service /etc/systemd/system/consul.service

systemctl enable consul.service
systemctl start consul.service
sleep 10


# Assemble arrays of Consul clients
declare -a CONSUL_CLIENTS=()
declare -a OTHER_CONSUL_CLIENTS=()
for i in $(consul members | awk '/client/ {print $1}'); do CONSUL_CLIENTS+=($i); done
for i in $(consul members | grep -v $(hostname) | awk '/client/ {print $1}')
  do OTHER_CONSUL_CLIENTS+=($i)
done


# Nomad

## Replace existing Nomad binary if remote file exists
if [[ `wget -S --spider $NOMAD_BINARY  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; then
  curl -L $NOMAD_BINARY > nomad.zip
  unzip -o nomad.zip -d /usr/local/bin
  chmod 0755 /usr/local/bin/nomad
  chown root:root /usr/local/bin/nomad
fi

cp $CONFIGDIR/nomad_client.hcl $NOMADCONFIGDIR/nomad.hcl
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


# Add Docker bridge network IP to /etc/resolv.conf (at the top)
echo "nameserver $DOCKER_BRIDGE_IP_ADDRESS" | tee /etc/resolv.conf.new
cat /etc/resolv.conf | tee --append /etc/resolv.conf.new
mv /etc/resolv.conf.new /etc/resolv.conf


# Set env vars for tool CLIs
echo "export VAULT_ADDR=http://$IP_ADDRESS:8200" | tee --append /home/$HOME_DIR/.bashrc
echo "export NOMAD_ADDR=http://$IP_ADDRESS:4646" | tee --append /home/$HOME_DIR/.bashrc


# GlusterFS
mkfs.xfs -i size=512 /dev/nvme1n1
mkdir -p /data/brick1/gv0
echo '/dev/nvme1n1 /data/brick1 xfs defaults 1 2' >> /etc/fstab
mount -a
echo "$(hostname):/gv0 /mnt glusterfs defaults,_netdev 0 0" >> /etc/fstab

apt update && apt install -y glusterfs-server
systemctl enable glusterd.service && systemctl start glusterd.service

printf "\n\n\n $(date) - GLUSTER ENABLED AND STARTED\n\n\n"


if [ ${#CONSUL_CLIENTS[@]} -le 3 ] # The setup is meant only for the first three nodes
then
  sleep 10 # Wait for other nodes in case they are not ready
  for i in ${OTHER_CONSUL_CLIENTS[*]}; do gluster peer probe $i || echo "$i already probed"; done
  gluster peer status # for user-data log diagnostics
  if [ ${CONSUL_CLIENTS[0]} = $(hostname) ] # A single node should run the following
  then
    gluster volume create gv0 replica 3 \
      ${CONSUL_CLIENTS[0]}:/data/brick1/gv0 \
      ${CONSUL_CLIENTS[1]}:/data/brick1/gv0 \
      ${CONSUL_CLIENTS[2]}:/data/brick1/gv0
    gluster volume start gv0
    gluster volume info # for user-data log diagnostics
    printf "\n\n\n $(date) - VOLUME CREATED AND STARTED\n\n\n"
  else
    sleep 10 # Give host 0 extra time to create the volume
  fi
  printf "\n\n\n $(date) - MOUNTING VOLUME\n\n\n"
  mount -a
fi
