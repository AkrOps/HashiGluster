#!/bin/bash

# Simple script that generates and distributes the certificates needed for Consul RPC and consensus
# communication to be secured over TLS.

# More info about the process here: https://learn.hashicorp.com/tutorials/consul/tls-encryption-secure

# Requirements:
# - Local Consul binary under PATH, since this script relies on its builtin CA.
# - ssh access to the server nodes in the cluster.
# - Run from the root directory of the HashiGluster Terraform environment/module.
# - Local Terraform binary under PATH.

# NOTE: this script DOES NOT take a ZERO-DOWNTIME approach, so it's meant to be run right after
# provisioning the cluster and before having any services running in it.

# WARNING: we will most likely not assign public IPs to the cluster nodes in the future and
# restrict ssh access through a VPN only.


# Most likely you will have just created the cluster, so we'll skip strict host checking
shopt -s expand_aliases
alias ssh="ssh -l ubuntu -o StrictHostKeyChecking=accept-new"

# The server and CA certificates will end up in certs/ - KEEP THE DIR UNDER GITIGNORE!
mkdir -p certs
if [ "$(ls certs/)" ]
then
    echo 'Error: certs directory must be empty. Backup previous certs if needed!'
    exit 1
fi

declare -a SERVER_IPs=()
declare -a CLIENT_IPs=()
for i in $(terraform output | grep 'Server public IPs' | grep -oP '(\d+\.){3}\d+'); do SERVER_IPs+=($i); done
for i in $(terraform output | grep 'Client public IPs' | grep -oP '(\d+\.){3}\d+'); do CLIENT_IPs+=($i); done

cd certs
consul tls ca create

for ((i=0; i<${#SERVER_IPs[@]}; i++))
do
    consul tls cert create -server -dc dc1 # TODO: take the datacenter name as an argument
    scp consul-agent-ca.pem dc1-server-consul-$i*.pem ubuntu@${SERVER_IPs[$i]}:/ops/shared
    ssh ubuntu@${SERVER_IPs[$i]} "
        sudo mkdir -p /opt/consul/data/certs
        sudo mv /ops/shared/*.pem /opt/consul/data/certs
        sudo chown root: /opt/consul/data/certs/*
        sudo chmod 600 /opt/consul/data/certs/*
        sudo cp /ops/shared/config/consul_server_tls_encrypt.hcl /etc/consul.d/
        sudo sed -i 's/HOST_NUMBER/$i/' /etc/consul.d/consul_server_tls_encrypt.hcl
        sudo systemctl restart consul.service
    "
    sleep 2
done

for ((i=0; i<${#CLIENT_IPs[@]}; i++))
do
    scp consul-agent-ca.pem ubuntu@${CLIENT_IPs[$i]}:/ops/shared
    ssh ubuntu@${CLIENT_IPs[$i]} "
        sudo mkdir -p /opt/consul/data/certs
        sudo mv /ops/shared/*.pem /opt/consul/data/certs
        sudo chown root: /opt/consul/data/certs/*
        sudo chmod 600 /opt/consul/data/certs/*
        sudo cp /ops/shared/config/consul_client_tls_encrypt.hcl /etc/consul.d/
        sudo systemctl restart consul.service
    "
    sleep 2
done

echo 'Certificates generated under certs/ and copied into the servers'
echo 'KEEP THE DIRECTORY CONTENT SAFE AND PRIVATE!'
