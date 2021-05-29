# Provision a production HashiStack cluster in the cloud

This project leverages [Hashicorp](https://www.hashicorp.com/) tools (known as the Hashicorp stack or HashiStack) in order to provision a production-ready [Nomad](https://www.nomadproject.io/), [Consul](https://www.consul.io) and [Vault](https://www.vaultproject.io) cluster in the cloud using [Packer](https://packer.io) and [Terraform](https://terraform.io).

This repository is based on [Nomad's official repository setup](https://github.com/hashicorp/nomad/tree/main/terraform), but with a few key differences and objectives:

- The base AMI Ubuntu version has been bumped from 16.04 to 20.04 and the setup has been adapted to it.
- We are using the latest version of every binary (Nomad, Consul, Vault and [Consul Template](https://github.com/hashicorp/consul-template)).
- We want to automate the ACL config and bootstraping process for all three components.
- The setup is focused on AWS only. We will later attempt to replicate the setup in Hetzner Cloud.
- We are aiming at a more robust and modern AWS setup, e.g. by allowing to deploy in a specific VPC and replacing the AWS Classic ELB with an ALB.

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

