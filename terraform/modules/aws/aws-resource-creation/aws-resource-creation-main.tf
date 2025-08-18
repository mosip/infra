terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# provider "aws" {
# Profile `default` means it will take credentials AWS_SITE_KEY & AWS_SECRET_EKY from ~/.aws/config under `default` section.
# profile = "default"
# region = "ap-south-1"
# }


resource "aws_security_group" "security-group" {
  for_each = var.SECURITY_GROUP
  vpc_id   = var.VPC_ID
  tags = {
    Name    = "${var.CLUSTER_NAME}-${each.key}"
    Cluster = var.CLUSTER_NAME
  }
  description = "Rules which allow the outgoing traffic from the instances associated with the security group ${each.key}"

  dynamic "ingress" {
    for_each = each.value
    iterator = port
    content {
      description      = port.value.description
      from_port        = port.value.from_port
      to_port          = port.value.to_port
      protocol         = port.value.protocol
      cidr_blocks      = port.value.cidr_blocks
      ipv6_cidr_blocks = port.value.ipv6_cidr_blocks
    }
  }
  egress {
    description      = "Allow HTTP outbound to anywhere (for package downloads)"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow HTTPS outbound to anywhere"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow WireGuard VPN outbound to VPN CIDR"
    from_port        = 51820
    to_port          = 51820
    protocol         = "udp"
    cidr_blocks      = [var.WIREGUARD_CIDR]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow DNS TCP outbound to anywhere (for public DNS resolution)"
    from_port        = 53
    to_port          = 53
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow DNS UDP outbound to anywhere (for public DNS resolution)"
    from_port        = 53
    to_port          = 53
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow all required internal communication to VPC CIDR"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  # Add more egress blocks for other trusted external IPs/services as needed
}

resource "aws_instance" "NGINX_EC2_INSTANCE" {

  ami                         = local.NGINX_INSTANCE.ami
  instance_type               = local.NGINX_INSTANCE.instance_type
  associate_public_ip_address = true  # Always true - NGINX needs public IP in both scenarios
  key_name                    = local.NGINX_INSTANCE.key_name
  user_data                   = lookup(local.NGINX_INSTANCE, "user_data", "")
  vpc_security_group_ids      = local.NGINX_INSTANCE.security_groups
  subnet_id                   = var.PUBLIC_SUBNET_IDS[0]

  ## for ssl certificate generation
  iam_instance_profile = aws_iam_instance_profile.certbot_profile.name


  root_block_device {
    volume_size           = local.NGINX_INSTANCE.root_block_device.volume_size
    volume_type           = local.NGINX_INSTANCE.root_block_device.volume_type
    delete_on_termination = local.NGINX_INSTANCE.root_block_device.delete_on_termination
    encrypted             = local.NGINX_INSTANCE.root_block_device.encrypted
    tags                  = local.NGINX_INSTANCE.root_block_device.tags
  }

  dynamic "ebs_block_device" {
    for_each = local.NGINX_INSTANCE.ebs_block_device
    iterator = ebs_volume
    content {
      device_name           = ebs_volume.value.device_name
      volume_size           = ebs_volume.value.volume_size
      volume_type           = ebs_volume.value.volume_type
      delete_on_termination = ebs_volume.value.delete_on_termination
      encrypted             = ebs_volume.value.encrypted
      tags                  = ebs_volume.value.tags
    }
  }

  tags = {
    Name    = local.NGINX_INSTANCE.tags.Name
    Cluster = local.NGINX_INSTANCE.tags.Cluster
  }
}
resource "aws_instance" "K8S_CLUSTER_EC2_INSTANCE" {
  for_each = merge(
    { for idx in range(var.K8S_CONTROL_PLANE_NODE_COUNT) : "CONTROL-PLANE-NODE-${idx + 1}" => idx },
    { for idx in range(var.K8S_ETCD_NODE_COUNT) : "ETCD-NODE-${idx + 1}" => idx },
    { for idx in range(var.K8S_WORKER_NODE_COUNT) : "WORKER-NODE-${idx + 1}" => idx }
  )

  ami                         = local.K8S_EC2_NODE.ami
  instance_type               = local.K8S_EC2_NODE.instance_type
  associate_public_ip_address = false  # K8s instances always use private IPs
  key_name                    = local.K8S_EC2_NODE.key_name
  subnet_id                   = var.PRIVATE_SUBNET_IDS[each.value % length(var.PRIVATE_SUBNET_IDS)]
  user_data = templatefile("${path.module}/rke-user-data.sh.tpl", {
    index          = each.value
    role           = each.key
    cluster_domain = var.CLUSTER_NAME
  })

  vpc_security_group_ids = [
    can(regex("CONTROL-PLANE-NODE", each.key)) ? aws_security_group.security-group["K8S_CONTROL_PLANE_SECURITY_GROUP"].id :
    can(regex("ETCD-NODE", each.key)) ? aws_security_group.security-group["K8S_ETCD_SECURITY_GROUP"].id : aws_security_group.security-group["K8S_WORKER_SECURITY_GROUP"].id
  ]

  root_block_device {
    volume_size           = local.K8S_EC2_NODE.root_block_device.volume_size
    volume_type           = local.K8S_EC2_NODE.root_block_device.volume_type
    delete_on_termination = local.K8S_EC2_NODE.root_block_device.delete_on_termination
    encrypted             = local.K8S_EC2_NODE.root_block_device.encrypted
    tags = {
      Name    = "${local.K8S_EC2_NODE.tags.Name}-${each.key}"
      Cluster = local.K8S_EC2_NODE.tags.Cluster
    }
  }

  tags = {
    Name    = "${local.K8S_EC2_NODE.tags.Name}-${each.key}"
    Cluster = local.K8S_EC2_NODE.tags.Cluster
  }
}

resource "aws_route53_record" "DNS_RECORDS" {
  for_each = merge(local.MAP_DNS_TO_IP, var.DNS_RECORDS)
  name     = each.value.name
  type     = each.value.type
  zone_id  = each.value.zone_id
  ttl      = each.value.ttl
  records  = [each.value.records]
  # health_check_id = each.value.health_check_id // Uncomment if using health checks
  allow_overwrite = each.value.allow_overwrite
}
