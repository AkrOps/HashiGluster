provider "aws" {
  region = var.region
}

module "hashistack" {
  source = "./modules/hashistack"

  name                               = var.name
  region                             = var.region
  ami                                = var.ami
  server_instance_type               = var.server_instance_type
  client_instance_type               = var.client_instance_type
  key_name                           = var.key_name
  server_count                       = var.server_count
  client_count                       = var.client_count
  retry_join                         = var.retry_join
  server_root_ebs_size               = var.server_root_ebs_size
  client_root_ebs_size               = var.client_root_ebs_size
  gluster_ebs_size                   = var.gluster_ebs_size
  delete_gluster_vols_on_termination = var.delete_gluster_vols_on_termination
  whitelist_ip                       = var.whitelist_ip
}
