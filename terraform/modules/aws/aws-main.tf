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

# Data source to check K8s instance type availability in each AZ
data "aws_ec2_instance_type_offerings" "k8s_instance_types" {
  for_each = toset(data.aws_availability_zones.available.names)

  filter {
    name   = "instance-type"
    values = [var.K8S_INSTANCE_TYPE]
  }

  filter {
    name   = "location"
    values = [each.value]
  }

  location_type = "availability-zone"
}

# Data source to check NGINX instance type availability in each AZ
data "aws_ec2_instance_type_offerings" "nginx_instance_types" {
  for_each = toset(data.aws_availability_zones.available.names)

  filter {
    name   = "instance-type"
    values = [var.NGINX_INSTANCE_TYPE]
  }

  filter {
    name   = "location"
    values = [each.value]
  }

  location_type = "availability-zone"
}

# Local variables for dynamic AZ selection
locals {
  # Get AZs where K8s instance type is available
  k8s_available_azs = [
    for az in data.aws_availability_zones.available.names :
    az if length(data.aws_ec2_instance_type_offerings.k8s_instance_types[az].instance_types) > 0
  ]

  # Get AZs where NGINX instance type is available
  nginx_available_azs = [
    for az in data.aws_availability_zones.available.names :
    az if length(data.aws_ec2_instance_type_offerings.nginx_instance_types[az].instance_types) > 0
  ]

  # Dynamic problematic AZ detection
  # Uses configurable exclusion lists when needed, defaults to empty (fully dynamic)
  k8s_capacity_excluded_azs   = var.k8s_capacity_excluded_azs
  nginx_capacity_excluded_azs = var.nginx_capacity_excluded_azs

  # Filter out problematic AZs
  k8s_filtered_azs = [
    for az in local.k8s_available_azs :
    az if !contains(local.k8s_capacity_excluded_azs, az)
  ]

  nginx_filtered_azs = [
    for az in local.nginx_available_azs :
    az if !contains(local.nginx_capacity_excluded_azs, az)
  ]

  # Smart selection: Use intersection of both filtered lists, with fallbacks
  # Calculate total K8s nodes that will be deployed
  total_k8s_nodes = var.K8S_CONTROL_PLANE_NODE_COUNT + var.K8S_ETCD_NODE_COUNT + var.K8S_WORKER_NODE_COUNT

  # Determine minimum AZs needed based on actual deployment
  # For K8s: Need enough AZs to distribute nodes (max 1 node per AZ for HA is ideal, but can pack more if needed)
  # For NGINX: Usually 1 instance, rarely 2
  min_azs_for_k8s   = min(local.total_k8s_nodes, 3) # Don't need more than 3 AZs even for large clusters
  min_azs_for_nginx = 1                             # NGINX typically runs on 1 instance

  common_available_azs = setintersection(toset(local.k8s_filtered_azs), toset(local.nginx_filtered_azs))

  # Dynamic selection based on actual requirements
  selected_azs = length(local.common_available_azs) >= local.min_azs_for_k8s ? tolist(local.common_available_azs) : (
    length(local.k8s_filtered_azs) >= local.min_azs_for_k8s ? local.k8s_filtered_azs :
    length(local.k8s_available_azs) >= local.min_azs_for_k8s ? local.k8s_available_azs :
    data.aws_availability_zones.available.names
  )
}

# Validation checks
resource "null_resource" "instance_type_validation" {
  triggers = {
    k8s_instance_type   = var.K8S_INSTANCE_TYPE
    nginx_instance_type = var.NGINX_INSTANCE_TYPE
    k8s_available_azs   = length(local.k8s_filtered_azs)
    nginx_available_azs = length(local.nginx_filtered_azs)
    common_azs          = length(local.common_available_azs)
    total_k8s_nodes     = local.total_k8s_nodes
    min_azs_needed      = local.min_azs_for_k8s
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Dynamic Instance Type & Capacity Validation ==="
      echo "K8s Instance Type: ${var.K8S_INSTANCE_TYPE}"
      echo "NGINX Instance Type: ${var.NGINX_INSTANCE_TYPE}"
      echo "Total AZs in region: ${length(data.aws_availability_zones.available.names)}"
      echo ""
      echo "K8s Cluster Configuration:"
      echo "  - Control Plane nodes: ${var.K8S_CONTROL_PLANE_NODE_COUNT}"
      echo "  - ETCD nodes: ${var.K8S_ETCD_NODE_COUNT}"
      echo "  - Worker nodes: ${var.K8S_WORKER_NODE_COUNT}"
      echo "  - Total K8s nodes: ${local.total_k8s_nodes}"
      echo "  - Minimum AZs needed: ${local.min_azs_for_k8s}"
      echo ""
      echo "K8s instance availability:"
      echo "  - API available AZs: ${join(", ", local.k8s_available_azs)}"
      echo "  - Capacity excluded AZs: ${join(", ", local.k8s_capacity_excluded_azs)}"
      echo "  - Filtered available AZs: ${join(", ", local.k8s_filtered_azs)}"
      echo ""
      echo "NGINX instance availability:"
      echo "  - API available AZs: ${join(", ", local.nginx_available_azs)}"
      echo "  - Capacity excluded AZs: ${join(", ", local.nginx_capacity_excluded_azs)}"
      echo "  - Filtered available AZs: ${join(", ", local.nginx_filtered_azs)}"
      echo ""
      echo "Common available AZs: ${join(", ", local.common_available_azs)}"
      echo "Selected AZs for deployment: ${join(", ", local.selected_azs)}"
      echo ""
      
      # Dynamic validation based on actual node requirements
      if [ ${length(local.k8s_filtered_azs)} -eq 0 ]; then
        echo "ERROR: K8s instance type ${var.K8S_INSTANCE_TYPE} has no available capacity!"
        echo "Consider using a different instance type or region."
        exit 1
      elif [ ${length(local.k8s_filtered_azs)} -lt ${local.min_azs_for_k8s} ]; then
        echo "WARNING: K8s needs ${local.min_azs_for_k8s} AZs for ${local.total_k8s_nodes} nodes, but only ${length(local.k8s_filtered_azs)} available!"
        echo "This may impact high availability and node distribution."
        if [ ${local.total_k8s_nodes} -gt 1 ]; then
          echo "Consider reducing node count or using a different instance type/region."
        fi
      else
        echo "SUCCESS: K8s has ${length(local.k8s_filtered_azs)} AZs available for ${local.total_k8s_nodes} nodes."
        echo "This allows good distribution across AZs for high availability."
      fi
      
      if [ ${length(local.nginx_filtered_azs)} -eq 0 ]; then
        echo "ERROR: NGINX instance type ${var.NGINX_INSTANCE_TYPE} has no available capacity!"
        echo "Consider using a different instance type or region."
        exit 1
      else
        echo "SUCCESS: NGINX instance type ${var.NGINX_INSTANCE_TYPE} is available in ${length(local.nginx_filtered_azs)} AZs."
      fi
      echo "=============================================="
    EOT
  }
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
        description : "SSH login port (temporary external access for deployment)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR, "0.0.0.0/0"],
        ipv6_cidr_blocks = []
      },
      {
        description : "Allow ICMP within VPC CIDR and WireGuard CIDR"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR],
        ipv6_cidr_blocks = []
      },
      {
        description : "HTTP port (public)"
        from_port : 80,
        to_port : 80,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = []
      },
      {
        description : "HTTPS port (public)"
        from_port : 443,
        to_port : 443,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = []
      },
      {
        description : "Minio console port (internal only)"
        from_port : 9000,
        to_port : 9000,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "Postgres port (internal only)"
        from_port : 5432,
        to_port : 5432,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "Postgres alternative port (internal only)"
        from_port : 5433,
        to_port : 5433,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "ActiveMQ port (internal only)"
        from_port : 61616,
        to_port : 61616,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "NFS server port tcp (internal only)"
        from_port : 2049,
        to_port : 2049,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "NFS server port udp (internal only)"
        from_port : 2049,
        to_port : 2049,
        protocol : "UDP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
    ]
    K8S_CONTROL_PLANE_SECURITY_GROUP = [
      {
        description : "SSH login port (restricted to VPC CIDR and WireGuard CIDR)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR],
        ipv6_cidr_blocks = []
      },
      {
        description : "Allow ICMP within VPC CIDR and WireGuard CIDR"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR],
        ipv6_cidr_blocks = []
      },
      {
        description : "Kubernetes API (internal only)"
        from_port : 6443,
        to_port : 6443,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "RKE2 supervisor API (internal only)"
        from_port : 9345,
        to_port : 9345,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "Kubelet metrics (internal only)"
        from_port : 10250,
        to_port : 10250,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "ETCD client port (internal only)"
        from_port : 2379,
        to_port : 2379,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "ETCD peer port (internal only)"
        from_port : 2380,
        to_port : 2380,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "ETCD metrics port (internal only)"
        from_port : 2381,
        to_port : 2381,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "NodePort port range (internal only)"
        from_port : 30000,
        to_port : 32767,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "Canal CNI with VXLAN (internal only)"
        from_port : 8472,
        to_port : 8472,
        protocol : "UDP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
      {
        description : "Canal CNI health checks (internal only)"
        from_port : 9099,
        to_port : 9099,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr],
        ipv6_cidr_blocks = []
      },
    ]
    K8S_ETCD_SECURITY_GROUP = [
      {
        description : "SSH login port (restricted to VPC CIDR and WireGuard CIDR)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR],
        ipv6_cidr_blocks = []
      },
      {
        description : "Allow ICMP within VPC CIDR and WireGuard CIDR"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR],
        ipv6_cidr_blocks = []
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
        description : "NodePort port range"
        from_port : 30000,
        to_port : 32767,
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
        description : "SSH login port (restricted to VPC CIDR and WireGuard CIDR)"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR],
        ipv6_cidr_blocks = []
      },
      {
        description : "Allow ICMP within VPC CIDR and WireGuard CIDR"
        from_port : -1,
        to_port : -1,
        protocol : "ICMP",
        cidr_blocks      = [var.network_cidr, var.WIREGUARD_CIDR],
        ipv6_cidr_blocks = []
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
  DNS_RECORDS = local.dns_records


  K8S_CONTROL_PLANE_NODE_COUNT = var.K8S_CONTROL_PLANE_NODE_COUNT
  K8S_ETCD_NODE_COUNT          = var.K8S_ETCD_NODE_COUNT
  K8S_WORKER_NODE_COUNT        = var.K8S_WORKER_NODE_COUNT
}


module "nginx-setup" {
  depends_on = [module.aws-resource-creation]
  #source     = "github.com/mosip/mosip-infra//deployment/v3/terraform/aws/modules/nginx-setup?ref=develop"
  source                                  = "./nginx-setup"
  NGINX_PUBLIC_IP                         = module.aws-resource-creation.NGINX_PUBLIC_IP
  CLUSTER_ENV_DOMAIN                      = var.CLUSTER_ENV_DOMAIN
  MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST = module.aws-resource-creation.MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST
  MOSIP_PUBLIC_DOMAIN_LIST                = module.aws-resource-creation.MOSIP_PUBLIC_DOMAIN_LIST
  CERTBOT_EMAIL                           = var.MOSIP_EMAIL_ID
  SSH_PRIVATE_KEY                         = var.SSH_PRIVATE_KEY
  K8S_INFRA_BRANCH                        = var.K8S_INFRA_BRANCH
  K8S_INFRA_REPO_URL                      = var.K8S_INFRA_REPO_URL
  NETWORK_CIDR                            = var.network_cidr
  MOSIP_INFRA_REPO_URL                    = var.mosip_infra_repo_url
  MOSIP_INFRA_BRANCH                      = var.mosip_infra_branch
  CONTROL_PLANE_HOST                      = [for instance in module.aws-resource-creation.K8S_CLUSTER_PRIVATE_IPS : instance][0]
  CONTROL_PLANE_USER                      = "ubuntu"
}


module "rke2-setup" {
  depends_on = [module.aws-resource-creation]
  #source     = "github.com/mosip/mosip-infra//deployment/v3/terraform/aws/modules/rke2-setup?ref=develop"
  source = "./rke2-cluster"

  SSH_PRIVATE_KEY         = var.SSH_PRIVATE_KEY
  K8S_INFRA_BRANCH        = var.K8S_INFRA_BRANCH
  K8S_CLUSTER_PRIVATE_IPS = module.aws-resource-creation.K8S_CLUSTER_PRIVATE_IPS
  RANCHER_IMPORT_URL      = var.RANCHER_IMPORT_URL
  K8S_INFRA_REPO_URL      = var.K8S_INFRA_REPO_URL
}

module "postgresql-setup" {
  count      = var.enable_postgresql_setup && var.nginx_node_ebs_volume_size_2 > 0 ? 1 : 0
  depends_on = [module.aws-resource-creation, module.rke2-setup, module.nfs-setup]
  source     = "./postgresql-setup"

  NGINX_PUBLIC_IP              = module.aws-resource-creation.NGINX_PUBLIC_IP
  SSH_PRIVATE_KEY              = var.SSH_PRIVATE_KEY
  NGINX_NODE_EBS_VOLUME_SIZE_2 = var.nginx_node_ebs_volume_size_2
  POSTGRESQL_VERSION           = var.postgresql_version
  STORAGE_DEVICE               = var.storage_device
  MOUNT_POINT                  = var.mount_point
  POSTGRESQL_PORT              = var.postgresql_port
  NETWORK_CIDR                 = var.network_cidr
  MOSIP_INFRA_REPO_URL         = var.mosip_infra_repo_url
  MOSIP_INFRA_BRANCH           = var.mosip_infra_branch

  # Control plane configuration for PostgreSQL K8s deployment
  CONTROL_PLANE_HOST = [for instance in module.aws-resource-creation.K8S_CLUSTER_PRIVATE_IPS : instance][0]
  CONTROL_PLANE_USER = "ubuntu"
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