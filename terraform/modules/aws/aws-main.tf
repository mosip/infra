variable "network_cidr" {
  description = "VPC CIDR block for internal communication and DNS rules"
  type        = string
}

variable "WIREGUARD_CIDR" {
  description = "CIDR block for WireGuard VPN server(s)"
  type        = string
}

# Data source to get all availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Use specific AZs if provided, otherwise use all available AZs
locals {
  selected_azs = length(var.SPECIFIC_AVAILABILITY_ZONES) > 0 ? var.SPECIFIC_AVAILABILITY_ZONES : data.aws_availability_zones.available.names
}

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

locals {
  homepage_dns_record = {
    "${var.CLUSTER_ENV_DOMAIN}" = {
      name            = var.CLUSTER_ENV_DOMAIN
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api-internal.${var.CLUSTER_ENV_DOMAIN}"
      allow_overwrite = true
    }
  }

  public_dns_records = {
    for sub in var.SUBDOMAIN_PUBLIC :
    sub => {
      name            = "${sub}.${var.CLUSTER_ENV_DOMAIN}"
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api.${var.CLUSTER_ENV_DOMAIN}"
      allow_overwrite = true
    }
  }

  internal_dns_records = {
    for sub in var.SUBDOMAIN_INTERNAL :
    sub => {
      name            = "${sub}.${var.CLUSTER_ENV_DOMAIN}"
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api-internal.${var.CLUSTER_ENV_DOMAIN}"
      allow_overwrite = true
    }
  }

  dns_records = merge(local.homepage_dns_record, local.public_dns_records, local.internal_dns_records)
}

# Data source to get existing VPC information
data "aws_vpc" "existing_vpc" {
  tags = {
    Name = var.vpc_name
  }
}

# Data source to get public subnets (using dynamically selected AZs)
data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }

  filter {
    name   = "availability-zone"
    values = local.selected_azs
  }

  tags = {
    Type = "Public"
  }
}

# Data source to get private subnets (using dynamically selected AZs)
data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }

  filter {
    name   = "availability-zone"
    values = local.selected_azs
  }

  tags = {
    Type = "Private"
  }
}

module "aws-resource-creation" {

  #source = "github.com/mosip/mosip-infra//deployment/v3/terraform/aws/modules/aws-resource-creation?ref=develop"
  source                        = "./aws-resource-creation"
  CLUSTER_NAME                  = var.CLUSTER_NAME
  AWS_PROVIDER_REGION           = var.AWS_PROVIDER_REGION
  SSH_KEY_NAME                  = var.SSH_KEY_NAME
  K8S_INSTANCE_TYPE             = var.K8S_INSTANCE_TYPE
  NGINX_INSTANCE_TYPE           = var.NGINX_INSTANCE_TYPE
  CLUSTER_ENV_DOMAIN            = var.CLUSTER_ENV_DOMAIN
  ZONE_ID                       = var.ZONE_ID
  AMI                           = var.AMI
  K8S_INSTANCE_ROOT_VOLUME_SIZE = var.K8S_INSTANCE_ROOT_VOLUME_SIZE

  NGINX_NODE_EBS_VOLUME_SIZE   = var.NGINX_NODE_EBS_VOLUME_SIZE
  NGINX_NODE_EBS_VOLUME_SIZE_2 = var.nginx_node_ebs_volume_size_2
  NGINX_NODE_ROOT_VOLUME_SIZE  = var.NGINX_NODE_ROOT_VOLUME_SIZE

  # VPC and Subnet Configuration
  VPC_ID             = data.aws_vpc.existing_vpc.id
  PUBLIC_SUBNET_IDS  = data.aws_subnets.public_subnets.ids
  PRIVATE_SUBNET_IDS = data.aws_subnets.private_subnets.ids

  network_cidr   = var.network_cidr
  WIREGUARD_CIDR = var.WIREGUARD_CIDR

  SECURITY_GROUP = {
    NGINX_SECURITY_GROUP = [
      {
        description : "SSH login port (open access)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow ICMP (open access)"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTP port (public)"
        from_port : 80,
        to_port : 80,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTPS port (public)"
        from_port : 443,
        to_port : 443,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Minio console port (open access)"
        from_port : 9000,
        to_port : 9000,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Postgres port (open access)"
        from_port : 5432,
        to_port : 5432,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Postgres alternative port (open access)"
        from_port : 5433,
        to_port : 5433,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ActiveMQ port (open access)"
        from_port : 61616,
        to_port : 61616,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NFS server port tcp (open access)"
        from_port : 2049,
        to_port : 2049,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NFS server port udp (open access)"
        from_port : 2049,
        to_port : 2049,
        protocol : "UDP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
    K8S_CONTROL_PLANE_SECURITY_GROUP = [
      {
        description : "SSH login port (open access)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow ICMP (open access)"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubernetes API (open access)"
        from_port : 6443,
        to_port : 6443,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "RKE2 supervisor API (open access)"
        from_port : 9345,
        to_port : 9345,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubelet metrics (open access)"
        from_port : 10250,
        to_port : 10250,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD client port (open access)"
        from_port : 2379,
        to_port : 2379,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD peer port (open access)"
        from_port : 2380,
        to_port : 2380,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD metrics port (open access)"
        from_port : 2381,
        to_port : 2381,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NodePort port range (open access)"
        from_port : 30000,
        to_port : 32767,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI with VXLAN (open access)"
        from_port : 8472,
        to_port : 8472,
        protocol : "UDP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI health checks (open access)"
        from_port : 9099,
        to_port : 9099,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "PostgreSQL port (open access)"
        from_port : 5433,
        to_port : 5433,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
    K8S_ETCD_SECURITY_GROUP = [
      {
        description : "SSH login port (open access)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow ICMP (open access)"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubelet metrics (open access)"
        from_port : 10250,
        to_port : 10250,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NodePort port range (open access)"
        from_port : 30000,
        to_port : 32767,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD client port (open access)"
        from_port : 2379,
        to_port : 2379,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD peer port (open access)"
        from_port : 2380,
        to_port : 2380,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD metrics port (open access)"
        from_port : 2381,
        to_port : 2381,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI with VXLAN (open access)"
        from_port : 8472,
        to_port : 8472,
        protocol : "UDP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI health checks (open access)"
        from_port : 9099,
        to_port : 9099,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr]],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "PostgreSQL port (open access)"
        from_port : 5433,
        to_port : 5433,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
    K8S_WORKER_SECURITY_GROUP = [
      {
        description : "SSH login port (open access)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow ICMP (open access)"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubelet metrics (open access)"
        from_port : 10250,
        to_port : 10250,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NodePort port range (open access)"
        from_port : 30000,
        to_port : 32767,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI with VXLAN (open access)"
        from_port : 8472,
        to_port : 8472,
        protocol : "UDP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI health checks (open access)"
        from_port : 9099,
        to_port : 9099,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "PostgreSQL port (open access)"
        from_port : 5433,
        to_port : 5433,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
  }
  DNS_RECORDS = local.dns_records


  K8S_CONTROL_PLANE_NODE_COUNT = var.K8S_CONTROL_PLANE_NODE_COUNT
  K8S_ETCD_NODE_COUNT          = var.K8S_ETCD_NODE_COUNT
  K8S_WORKER_NODE_COUNT        = var.K8S_WORKER_NODE_COUNT
}
