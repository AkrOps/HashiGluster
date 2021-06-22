variable "name" {}

variable "region" {}

variable "ami" {}

variable "server_instance_type" {}

variable "client_instance_type" {}

variable "gluster_instance_type" {}

variable "key_name" {}

variable "server_count" {}

variable "client_count" {}

variable "gluster_count" {}

variable "root_block_device_size" {}

variable "gluster_block_device_size" {}

variable "delete_gluster_vols_on_termination" {}

variable "whitelist_ip" {}

variable "retry_join" {
  type = map(string)

  default = {
    provider  = "aws"
    tag_key   = "ConsulAutoJoin"
    tag_value = "auto-join"
  }
}

locals {
  AZs = ["a", "b", "c"]
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "server_lb" {
  name   = "${var.name}-server-lb"
  vpc_id = data.aws_vpc.default.id

  # Nomad
  ingress {
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  # Consul
  ingress {
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  # Vault
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "primary" {
  name   = var.name
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  # Nomad
  ingress {
    from_port       = 4646
    to_port         = 4646
    protocol        = "tcp"
    cidr_blocks     = [var.whitelist_ip]
    security_groups = [aws_security_group.server_lb.id]
  }

  # Fabio 
  ingress {
    from_port   = 9998
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = [var.whitelist_ip]
  }

  # Consul
  ingress {
    from_port       = 8500
    to_port         = 8500
    protocol        = "tcp"
    cidr_blocks     = [var.whitelist_ip]
    security_groups = [aws_security_group.server_lb.id]
  }

  # Vault
  ingress {
    from_port       = 8200
    to_port         = 8200
    protocol        = "tcp"
    cidr_blocks     = [var.whitelist_ip]
    security_groups = [aws_security_group.server_lb.id]
  }

  # Nginx
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "template_file" "user_data_server" {
  template = file("${path.root}/scripts/user-data-server-v2.sh")

  vars = {
    server_count = var.server_count
    region       = var.region
    retry_join = chomp(
      join(
        " ",
        formatlist("%s=%s", keys(var.retry_join), values(var.retry_join)),
      ),
    )
  }
}

data "template_file" "user_data_client" {
  template = file("${path.root}/scripts/user-data-client.sh")

  vars = {
    region = var.region
    retry_join = chomp(
      join(
        " ",
        formatlist("%s=%s ", keys(var.retry_join), values(var.retry_join)),
      ),
    )
  }
}

data "template_file" "user_data_gluster" {
  template = file("${path.root}/scripts/user-data-gluster.sh")

  vars = {
    region = var.region
    retry_join = chomp(
      join(
        " ",
        formatlist("%s=%s ", keys(var.retry_join), values(var.retry_join)),
      ),
    )
  }
}

resource "aws_instance" "server" {
  ami                    = var.ami
  instance_type          = var.server_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.primary.id]
  count                  = var.server_count
  availability_zone = "${var.region}${local.AZs[count.index % 3]}"

  # instance tags
  tags = merge(
    {
      "Name" = "${var.name}-server-${count.index}"
    },
    {
      "${var.retry_join.tag_key}" = "${var.retry_join.tag_value}"
    },
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_block_device_size
    delete_on_termination = true
  }

  user_data            = data.template_file.user_data_server.rendered
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
}

resource "aws_instance" "client" {
  ami                    = var.ami
  instance_type          = var.client_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.primary.id]
  count                  = var.client_count
  availability_zone      = "${var.region}${local.AZs[count.index % 3]}"
  depends_on             = [aws_instance.server, aws_instance.gluster]

  # instance tags
  tags = merge(
    {
      "Name" = "${var.name}-client-${count.index}"
    },
    {
      "${var.retry_join.tag_key}" = "${var.retry_join.tag_value}"
    },
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_block_device_size
    delete_on_termination = var.delete_gluster_vols_on_termination
  }

  user_data            = data.template_file.user_data_client.rendered
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
}

resource "aws_instance" "gluster" {
  ami                    = var.ami
  instance_type          = var.gluster_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.primary.id]
  count                  = var.gluster_count
  availability_zone      = "${var.region}${local.AZs[count.index % 3]}"
  depends_on             = [aws_instance.server]

  # instance tags
  tags = merge(
    {
      Name = "${var.name}-gluster-${count.index}"
    },
    {
      "${var.retry_join.tag_key}" = "${var.retry_join.tag_value}"
    },
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_block_device_size
    delete_on_termination = true
  }

  user_data            = data.template_file.user_data_gluster.rendered
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
}

resource "aws_ebs_volume" "gluster" {
  count             = var.server_count
  availability_zone = "${var.region}${local.AZs[count.index % 3]}"
  type              = "gp3"
  size              = var.gluster_block_device_size

  tags = {
    Name = "${var.name}-gluster-${count.index}"
  }
}

resource "aws_volume_attachment" "gluster" {
  count       = var.server_count
  device_name = "/dev/xvdd"
  volume_id   = aws_ebs_volume.gluster[count.index].id
  instance_id = aws_instance.server[count.index].id
}

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = var.name
  role        = aws_iam_role.instance_role.name
}

resource "aws_iam_role" "instance_role" {
  name_prefix        = var.name
  assume_role_policy = data.aws_iam_policy_document.instance_role.json
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "auto_discover_cluster" {
  name   = "auto-discover-cluster"
  role   = aws_iam_role.instance_role.id
  policy = data.aws_iam_policy_document.auto_discover_cluster.json
}

data "aws_iam_policy_document" "auto_discover_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "autoscaling:DescribeAutoScalingGroups",
    ]

    resources = ["*"]
  }
}

resource "aws_elb" "server_lb" {
  name               = "${var.name}-server-lb"
  availability_zones = distinct(aws_instance.server.*.availability_zone)
  internal           = false
  instances          = aws_instance.server.*.id

  listener {
    instance_port     = 4646
    instance_protocol = "http"
    lb_port           = 4646
    lb_protocol       = "http"
  }

  listener {
    instance_port     = 8500
    instance_protocol = "http"
    lb_port           = 8500
    lb_protocol       = "http"
  }

  listener {
    instance_port     = 8200
    instance_protocol = "http"
    lb_port           = 8200
    lb_protocol       = "http"
  }

  security_groups = [aws_security_group.server_lb.id]
}

output "server_public_ips" {
   value = aws_instance.server[*].public_ip
}

output "client_public_ips" {
   value = aws_instance.client[*].public_ip
}

output "gluster_public_ips" {
   value = aws_instance.gluster[*].public_ip
}

output "server_lb_ip" {
  value = aws_elb.server_lb.dns_name
}

