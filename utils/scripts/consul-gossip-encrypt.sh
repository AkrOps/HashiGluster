#!/bin/bash

# This scripts enables Gossip encryption for all Consul agents.
# It should be run from inside the Terraform environment and ssh access to the hosts is needed.
# This process has already been integrated into the server and client user-data scripts.

shopt -s expand_aliases
CONFIG_FILE="/etc/consul.d/consul.hcl"
alias ssh="ssh -l ubuntu -o StrictHostKeyChecking=accept-new"

declare -a HOST_IPs=()

for i in $(terraform output | grep 'public IPs' | grep -oP '(\d+\.){3}\d+'); do HOST_IPs+=($i); done

# Grab encryption key if it exists (cat to local sed to reduce complexity)
KEY=$(ssh ${HOST_IPs[0]} cat $CONFIG_FILE | sed -rn 's/encrypt = "(.+)"/\1/p')

# Otherwise, generate a new key
if ! [ $KEY ]; then
	KEY=$(ssh ${HOST_IPs[0]} consul keygen)
fi

# Add encryption key to consul agent config
for i in ${HOST_IPs[@]}; do
	if ! [ "$(ssh $i grep -o 'encrypt' $CONFIG_FILE)" ]; then ssh $i "printf '\n\nencrypt = \"$KEY\"\n' | sudo tee -a $CONFIG_FILE"; fi
done

# Restart Consul service
for i in ${HOST_IPs[@]}; do ssh $i 'sudo systemctl restart consul'; done
