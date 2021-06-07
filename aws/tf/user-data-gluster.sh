#!/bin/bash

set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

printf "\n\nSTARTING AT $(date)\n\n"

CONFIGDIR=/ops/shared/config

CONSULCONFIGDIR=/etc/consul.d
NOMADCONFIGDIR=/etc/nomad.d
HOME_DIR=ubuntu
AWS_DATA_IP=169.254.169.254

# Wait for network
sleep 10

DOCKER_BRIDGE_IP_ADDRESS=(`ifconfig docker0 2>/dev/null | awk '/inet / {print $2}'`)
RETRY_JOIN="${retry_join}"

# Get IP address and AZ from metadata service
IP_ADDRESS=$(curl http://$AWS_DATA_IP/latest/meta-data/local-ipv4)
AZ=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone/ | grep -o '.$')

# Adapt the hostname to our naming convention
NEW_HOSTNAME="gs-$AZ-$(hostname | grep -Po '\d+\-\d+$')"
hostname $NEW_HOSTNAME
hostnamectl set-hostname $NEW_HOSTNAME

# Consul
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/consul_client.hcl
sed -i "s/RETRY_JOIN/$RETRY_JOIN/g" $CONFIGDIR/consul_client.hcl
cp $CONFIGDIR/consul_client.hcl $CONSULCONFIGDIR/consul.hcl
cp $CONFIGDIR/consul_aws.service /etc/systemd/system/consul.service

systemctl enable consul.service
systemctl start consul.service
sleep 10 # Wait for other Consul clients


# Assemble arrays of GlusterFS servers (also Consul clients)
DC=$(consul members | grep $(hostname) | awk '{ print $7 }') # Consul datacenter
CONSUL_DOM=".node.$DC.consul"
declare -a GLUSTER_NODES=()
declare -a OTHER_GLUSTER_NODES=()
for i in $(consul members | awk '/gs-/ {print $1}'); do GLUSTER_NODES+=($i$CONSUL_DOM); done
for i in $(consul members | grep -v $(hostname) | awk '/gs-/ {print $1}')
  do OTHER_GLUSTER_NODES+=($i$CONSUL_DOM)
done
CLUSTER_SIZE=$${#GLUSTER_NODES[@]}

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

apt update && apt install -y glusterfs-server
systemctl enable glusterd.service && systemctl start glusterd.service

sleep 10 # Wait for other nodes in case they are not ready
for i in $${OTHER_GLUSTER_NODES[*]}; do gluster peer probe $i || echo "$i already probed"; done
gluster peer status # for user-data log diagnostics


if [ $(echo $${GLUSTER_NODES[0]} | grep "^$(hostname)") ] # A single node should run the following
then
  gluster volume create gv0 replica $CLUSTER_SIZE \
    $(for i in $${GLUSTER_NODES[@]}; do echo "$i:/data/brick1/gv0 "; done)
  gluster volume start gv0
  gluster volume info # for user-data log diagnostics
fi
