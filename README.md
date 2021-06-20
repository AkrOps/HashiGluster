# HashiGluster

## Introduction

This project aims at provisioning a production-ready [Nomad](https://www.nomadproject.io/), [Consul](https://www.consul.io) and [Vault](https://www.vaultproject.io) cluster in the cloud, combined with a [GlusterFS](https://docs.gluster.org/en/latest/) cluster in order to provide shared, highly available storage for stateful workloads.

All infrastructure is kept as code and provisioned using [Terraform](https://terraform.io), and base AMIs are built using [Packer](https://packer.io) 

The project started as an attempt of updating [Nomad's official repository AWS setup](https://github.com/hashicorp/nomad/tree/main/terraform).

## Key features and objectives:

- Integrating GlusterFS network filesystem with host volumes for stateful workloads.
- Ensuring an even distribution of servers, clients and GlusterFS servers across AZs.
- Keeping the base AMI at the latest LTS Ubuntu version and adapting the setup to it.
- Using the latest version of every binary (Nomad, Consul, Vault and [Consul Template](https://github.com/hashicorp/consul-template)).
- Automating the process of securing Consul gossip communication with symmetric encryption.
- Securing Consul agent communication with TLS, automating both the initial bootstrap process for servers and the addition of every new client.
- Automating the ACL config and bootstraping process for Nomad and Consul and then managing all tokens with Vault.
- Provisioning the cluster in private subnets of a specific VPC.
- Replacing the AWS Classic ELB with an ALB.
- Restricting ssh access to nodes to a VPN.

## Provision a cluster

- Follow the steps [here](aws/README.md) to provision a cluster on AWS.
- Continue with the steps below after a cluster has been provisioned.

## Test

Run a few basic status commands to verify that Consul and Nomad are up and running 
properly:

```bash
$ consul members
$ nomad server members
$ nomad node status
```

## Unseal the Vault cluster (optional)

To initialize and unseal Vault, run:

```bash
$ vault operator init -key-shares=5 -key-threshold=3  # default
$ vault operator unseal
$ export VAULT_TOKEN=[INITIAL_ROOT_TOKEN]
```

The `vault init` command above unseals the Vault with the default settings: five key shares and a key  threshold of three. This is the minimum recommended setup for a production environment. It is also recommended to securely distribute the keys to independent  operators. If you provisioned more than one server, the others will 
become standby nodes but should still be unsealed. You can query the active 
and standby nodes independently:

```bash
$ dig active.vault.service.consul
$ dig active.vault.service.consul SRV
$ dig standby.vault.service.consul
```

## Getting started with Nomad & the HashiCorp stack

Use the following links to get started with Nomad and its HashiCorp integrations:

* [Getting Started with Nomad](https://www.nomadproject.io/intro/getting-started/jobs.html)
* [Consul integration](https://www.nomadproject.io/docs/service-discovery/index.html)
* [Vault integration](https://www.nomadproject.io/docs/vault-integration/index.html)
* [consul-template integration](https://www.nomadproject.io/docs/job-specification/template.html)

