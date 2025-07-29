terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# Data sources to fetch VPC and subnet information
data "aws_vpc" "existing_vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["Public"]
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["Private"]
  }
}

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

  # Validation and subnet selection
  public_subnet_ids = data.aws_subnets.public_subnets.ids
  private_subnet_ids = data.aws_subnets.private_subnets.ids

  # Common security group configuration
  security_groups = {
    NGINX_SECURITY_GROUP = [
      {
        description : "SSH login port"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow all incoming ICMP IPv4 and IPv6 traffic"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTP port"
        from_port : 80,
        to_port : 80,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTPS port"
        from_port : 443,
        to_port : 443,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Minio console port"
        from_port : 9000,
        to_port : 9000,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Postgres port"
        from_port : 5432,
        to_port : 5432,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ActiveMQ port"
        from_port : 61616,
        to_port : 61616,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NFS server port tcp"
        from_port : 2049,
        to_port : 2049,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NFS server port udp"
        from_port : 2049,
        to_port : 2049,
        protocol : "UDP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
    K8S_CONTROL_PLANE_SECURITY_GROUP = [
      {
        description : "SSH login port"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow all incoming ICMP IPv4 and IPv6 traffic"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubernetes API"
        from_port : 6443,
        to_port : 6443,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "RKE2 supervisor API"
        from_port : 9345,
        to_port : 9345,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubelet metrics"
        from_port : 10250,
        to_port : 10250,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD client port"
        from_port : 2379,
        to_port : 2379,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD peer port"
        from_port : 2380,
        to_port : 2380,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD metrics port"
        from_port : 2381,
        to_port : 2381,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NodePort port range"
        from_port : 30000,
        to_port : 32767,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI with VXLAN"
        from_port : 8472,
        to_port : 8472,
        protocol : "UDP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI health checks"
        from_port : 9099,
        to_port : 9099,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
    K8S_ETCD_SECURITY_GROUP = [
      {
        description : "SSH login port"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow all incoming ICMP IPv4 and IPv6 traffic"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD client port"
        from_port : 2379,
        to_port : 2379,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD peer port"
        from_port : 2380,
        to_port : 2380,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "ETCD metrics port"
        from_port : 2381,
        to_port : 2381,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubelet metrics"
        from_port : 10250,
        to_port : 10250,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "RKE2 supervisor API"
        from_port : 9345,
        to_port : 9345,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NodePort port range"
        from_port : 30000,
        to_port : 32767,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI with VXLAN"
        from_port : 8472,
        to_port : 8472,
        protocol : "UDP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI health checks"
        from_port : 9099,
        to_port : 9099,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
    K8S_WORKER_SECURITY_GROUP = [
      {
        description : "SSH login port"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Allow all incoming ICMP IPv4 and IPv6 traffic"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Kubelet metrics"
        from_port : 10250,
        to_port : 10250,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "RKE2 supervisor API"
        from_port : 9345,
        to_port : 9345,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "NodePort port range"
        from_port : 30000,
        to_port : 32767,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI with VXLAN"
        from_port : 8472,
        to_port : 8472,
        protocol : "UDP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Canal CNI health checks"
        from_port : 9099,
        to_port : 9099,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
    ]
  }
}

# Validation checks
locals {
  validate_public_subnets = length(local.public_subnet_ids) > 0 ? local.public_subnet_ids : null
  validate_private_subnets = length(local.private_subnet_ids) > 0 ? local.private_subnet_ids : null
}

# Error handling for missing subnets
resource "null_resource" "subnet_validation" {
  count = length(local.public_subnet_ids) == 0 || length(local.private_subnet_ids) == 0 ? 1 : 0
  
  provisioner "local-exec" {
    command = <<EOF
echo "ERROR: Subnets not found!"
echo "VPC: ${data.aws_vpc.existing_vpc.id} (${var.vpc_name})"
echo "Public subnets found: ${length(local.public_subnet_ids)}"
echo "Private subnets found: ${length(local.private_subnet_ids)}"
echo "Make sure your VPC has subnets tagged with 'Type=Public' and 'Type=Private'"
exit 1
EOF
  }
}

module "aws-resource-creation" {
  source                        = "./aws-resource-creation"
  CLUSTER_NAME                  = var.CLUSTER_NAME
  AWS_PROVIDER_REGION           = var.AWS_PROVIDER_REGION
  SSH_KEY_NAME                  = var.SSH_KEY_NAME
  K8S_INSTANCE_TYPE             = var.K8S_INSTANCE_TYPE
  NGINX_INSTANCE_TYPE           = var.NGINX_INSTANCE_TYPE
  CLUSTER_ENV_DOMAIN            = var.CLUSTER_ENV_DOMAIN
  ZONE_ID                       = var.ZONE_ID
  AMI                           = var.AMI
  VPC_ID                        = data.aws_vpc.existing_vpc.id
  PUBLIC_SUBNET_ID              = length(local.public_subnet_ids) > 0 ? local.public_subnet_ids[0] : null
  PRIVATE_SUBNET_IDS            = local.private_subnet_ids
  K8S_INSTANCE_ROOT_VOLUME_SIZE = var.K8S_INSTANCE_ROOT_VOLUME_SIZE

  NGINX_NODE_EBS_VOLUME_SIZE  = var.NGINX_NODE_EBS_VOLUME_SIZE
  NGINX_NODE_ROOT_VOLUME_SIZE = var.NGINX_NODE_ROOT_VOLUME_SIZE

  SECURITY_GROUP                = local.security_groups
  DNS_RECORDS                   = local.dns_records
  K8S_CONTROL_PLANE_NODE_COUNT  = var.K8S_CONTROL_PLANE_NODE_COUNT
  K8S_ETCD_NODE_COUNT           = var.K8S_ETCD_NODE_COUNT
  K8S_WORKER_NODE_COUNT         = var.K8S_WORKER_NODE_COUNT
}

module "nginx-setup" {
  depends_on = [module.aws-resource-creation]
  source                                  = "./nginx-setup"
  NGINX_PUBLIC_IP                         = module.aws-resource-creation.NGINX_PUBLIC_IP
  CLUSTER_ENV_DOMAIN                      = var.CLUSTER_ENV_DOMAIN
  MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST = module.aws-resource-creation.MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST
  MOSIP_PUBLIC_DOMAIN_LIST                = module.aws-resource-creation.MOSIP_PUBLIC_DOMAIN_LIST
  CERTBOT_EMAIL                           = var.MOSIP_EMAIL_ID
  SSH_PRIVATE_KEY                         = var.SSH_PRIVATE_KEY
  K8S_INFRA_BRANCH                        = var.K8S_INFRA_BRANCH
  K8S_INFRA_REPO_URL                      = var.K8S_INFRA_REPO_URL
}

module "rke2-setup" {
  depends_on = [module.aws-resource-creation]
  source = "./rke2-cluster"

  SSH_PRIVATE_KEY         = var.SSH_PRIVATE_KEY
  K8S_INFRA_BRANCH        = var.K8S_INFRA_BRANCH
  K8S_CLUSTER_PRIVATE_IPS = module.aws-resource-creation.K8S_CLUSTER_PRIVATE_IPS
  enable_rancher_import   = var.ENABLE_RANCHER_IMPORT
  RANCHER_IMPORT_URL      = var.RANCHER_IMPORT_URL
  K8S_INFRA_REPO_URL      = var.K8S_INFRA_REPO_URL
}

module "nfs-setup" {
  depends_on          = [module.aws-resource-creation, module.rke2-setup]
  source              = "./nfs-setup"
  NFS_SERVER_LOCATION = "/srv/nfs/mosip/${var.CLUSTER_ENV_DOMAIN}"
  NFS_SERVER          = module.aws-resource-creation.NGINX_PRIVATE_IP
  SSH_PRIVATE_KEY     = var.SSH_PRIVATE_KEY
  K8S_INFRA_REPO_URL  = var.K8S_INFRA_REPO_URL
  K8S_INFRA_BRANCH    = var.K8S_INFRA_BRANCH
  CLUSTER_NAME        = var.CLUSTER_NAME
}
