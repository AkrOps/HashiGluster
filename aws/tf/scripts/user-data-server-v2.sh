#!/bin/bash

# This script unifies user-data-server.sh and user-data-gluster.sh into one, therefore
# unifying HashiStack (Nomad, Consul, Vault) servers and GlusterFS servers, and also
# mounting the GlusterFS volume (becoming a client) in order to share files generated
# by HashiStack servers to the rest of the cluster.

set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

printf "\n\nSTARTING AT $(date)\n\n"

CONFIGDIR=/ops/shared/config

CONSULCONFIGDIR=/etc/consul.d
VAULTCONFIGDIR=/etc/vault.d
NOMADCONFIGDIR=/etc/nomad.d
CONSULTEMPLATECONFIGDIR=/etc/consul-template.d
CONSULSHAREDDIR=/mnt/consul-shared
HOME_DIR=ubuntu
AWS_DATA_IP=169.254.169.254
AWS_DNS=169.254.169.253


# Wait for network
sleep 15

DOCKER_BRIDGE_IP_ADDRESS=(`ifconfig docker0 2>/dev/null | awk '/inet / {print $2}'`)

SERVER_COUNT="${server_count}"
RETRY_JOIN="${retry_join}"


# Get IP address and AZ from metadata service
IP_ADDRESS=$(curl http://$AWS_DATA_IP/latest/meta-data/local-ipv4)
AZ=$(curl "http://$AWS_DATA_IP/latest/meta-data/placement/availability-zone/" | grep -o '.$')


# Adapt the hostname to our naming convention
NEW_HOSTNAME="hg-s-$AZ-$(hostname | grep -Po '\d+\-\d+$')"
hostname $NEW_HOSTNAME
hostnamectl set-hostname $NEW_HOSTNAME


# Consul
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/consul.hcl
sed -i "s/SERVER_COUNT/$SERVER_COUNT/g" $CONFIGDIR/consul.hcl
sed -i "s/RETRY_JOIN/$RETRY_JOIN/g" $CONFIGDIR/consul.hcl

cp $CONFIGDIR/consul.hcl $CONSULCONFIGDIR
cp $CONFIGDIR/consul_aws.service /etc/systemd/system/consul.service

systemctl enable consul.service
systemctl start consul.service

export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500
export CONSUL_RPC_ADDR=$IP_ADDRESS:8400

sleep 15


# Assemble arrays of Consul servers IPs (also GlusterFS servers)
declare -a SERVERS=()
for IP in $(consul members | grep server | awk '{ print $2 }' | sed -E 's/:.+$//')
  do SERVERS+=($IP)
done
SERVER_CLUSTER_SIZE=$${#SERVERS[@]}

# Add hostname to /etc/hosts
echo "127.0.0.1 $(hostname)" | tee --append /etc/hosts



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
echo "nameserver $AWS_DNS" | tee -a /etc/resolv.conf.new
cat /etc/resolv.conf | tee --append /etc/resolv.conf.new
mv /etc/resolv.conf.new /etc/resolv.conf


# Set env vars for tool CLIs
echo "export CONSUL_RPC_ADDR=$IP_ADDRESS:8400" | tee --append /home/$HOME_DIR/.bashrc
echo "export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500" | tee --append /home/$HOME_DIR/.bashrc
echo "export VAULT_ADDR=http://$IP_ADDRESS:8200" | tee --append /home/$HOME_DIR/.bashrc
echo "export NOMAD_ADDR=http://$IP_ADDRESS:4646" | tee --append /home/$HOME_DIR/.bashrc


# GlusterFS server
mkfs.xfs -i size=512 /dev/nvme1n1
mkdir -p /data/brick1/gv0
echo '/dev/nvme1n1 /data/brick1 xfs defaults 1 2' >> /etc/fstab
mount -a

apt update && apt install -y glusterfs-server
systemctl enable glusterd.service && systemctl start glusterd.service

sleep 15 # Wait for other nodes in case they are not ready
if [ $${SERVERS[0]} == $IP_ADDRESS ]
then
  for ((i=1; i<$SERVER_CLUSTER_SIZE; i++))
    do gluster peer probe $${SERVERS[$i]} || echo "$${SERVERS[$i]} already probed"
  done
elif [ $${SERVERS[1]} == $IP_ADDRESS ]
then
  gluster peer probe $${SERVERS[0]} || echo "$${SERVERS[$i]} already probed"
fi

sleep 15 # Give the chance for nodes to probe peers
gluster peer status # for user-data log diagnostics

if [ $${SERVERS[0]} == $IP_ADDRESS ] # Only the "first" node (in AZ a) should run the following
then
  gluster volume create gv0 replica $SERVER_CLUSTER_SIZE \
    $(for i in $${SERVERS[@]}; do echo "$i:/data/brick1/gv0 "; done)
  gluster volume start gv0
  gluster volume info # for user-data log diagnostics
  mount -t glusterfs "$NEW_HOSTNAME:/gv0" /mnt
  mkdir $CONSULSHAREDDIR
  GOSSIP_ENCRYPTION_KEY=$(consul keygen)
  sed -i "s@GOSSIP_ENCRYPTION_KEY@$GOSSIP_ENCRYPTION_KEY@g" $CONFIGDIR/consul_gossip_encrypt.hcl
  cp $CONFIGDIR/consul_gossip_encrypt.hcl $CONSULSHAREDDIR
  cp $CONFIGDIR/consul_gossip_encrypt.hcl $CONSULCONFIGDIR
  systemctl restart consul
else
  sleep 15
  mount -t glusterfs "$NEW_HOSTNAME:/gv0" /mnt
  cp $CONSULSHAREDDIR/consul_gossip_encrypt.hcl $CONSULCONFIGDIR
  systemctl restart consul
fi


# Mount GlusterFS volume
echo "$NEW_HOSTNAME:/gv0 /mnt glusterfs defaults,_netdev 0 0" >> /etc/fstab
mount -a || (sleep 30 && mount -a)
