variable "name" {
  description = "Used to name various infrastructure components"
}

variable "whitelist_ip" {
  description = "IP to whitelist for the security groups (set 0.0.0.0/0 for world)"
}

variable "region" {
  description = "The AWS region to deploy to."
  default     = "eu-west-1"
}

variable "ami" {}

variable "server_instance_type" {
  description = "The AWS instance type to use for servers."
  default     = "t3a.medium"
}

variable "client_instance_type" {
  description = "The AWS instance type to use for clients."
  default     = "t3a.medium"
}

variable "gluster_instance_type" {
  description = "The AWS instance type to use for GlusterFS servers."
  default     = "t3a.micro"
}

variable "root_block_device_size" {
  description = "The volume size of the root block device."
  default     = 60
}

variable "gluster_block_device_size" {
  description = "The size of the storage EBS volume for each GlusterFS server node."
  default     = 30
}

variable "delete_gluster_vols_on_termination" {
  default     = false
}

variable "key_name" {
  description = "Name of the SSH key used to provision EC2 instances."
}

variable "server_count" {
  description = "The number of servers to provision."
  default     = "3"
}

variable "client_count" {
  description = "The number of clients to provision."
  default     = "3"
}

variable "gluster_count" {
  description = "The number of GlusterFS nodes to provision."
  default     = "3"
}

variable "retry_join" {
  description = "Used by Consul to automatically form a cluster."
  type        = map(string)

  default = {
    provider  = "aws"
    tag_key   = "ConsulAutoJoin"
    tag_value = "auto-join"
  }
}
