# Environment name (infra component)
cluster_name = "soil"
# MOSIP's domain (ex: sandbox.xyz.net)
cluster_env_domain = "testgrid.mosip.net"
# Email-ID will be used by certbot to notify SSL certificate expiry via email
mosip_email_id = "chandra.mishra@technoforte.co.in"
# SSH login key name for AWS node instances (ex: my-ssh-key)
ssh_key_name = "mosip-aws"
# The AWS region for resource creation
aws_provider_region = "ap-south-1"

# Instance Types Configuration
# The infrastructure automatically validates both instance types across AZs and calculates
# optimal AZ distribution based on actual node counts:
# - K8s validation considers total nodes (control plane + etcd + worker)
# - NGINX typically runs 1 instance (can work with 1 AZ)
# - Dynamic calculation: min_azs_needed = min(total_k8s_nodes, 3)
# - Capacity exclusions are optional and configurable below

# The instance type for Kubernetes nodes (control plane, worker, etcd)
k8s_instance_type = "t3.2xlarge"
# The instance type for Nginx server (load balancer)
nginx_instance_type = "t3.2xlarge"

# Optional: Exclude specific AZs due to known capacity issues
# Leave empty for fully dynamic behavior (recommended)
# Add AZs only if you experience repeated capacity issues
k8s_capacity_excluded_azs   = [] # e.g., ["ap-south-1a"] if needed
nginx_capacity_excluded_azs = [] # e.g., ["ap-south-1a"] if needed
# The Route 53 hosted zone ID
zone_id = "Z090954828SJIEL6P5406"

## UBUNTU 24.04
# The Amazon Machine Image ID for the instances
ami = "ami-0ad21ae1d0696ad58"

# Repo K8S-INFRA URL
k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
# Repo K8S-INFRA branch
k8s_infra_branch = "develop"
# NGINX Node's Root volume size
nginx_node_root_volume_size = 24
# NGINX node's EBS volume size
nginx_node_ebs_volume_size = 300
# NGINX node's second EBS volume size (optional - set to 0 to disable)
nginx_node_ebs_volume_size_2 = 200 # Enable second EBS volume for PostgreSQL testing
# Kubernetes nodes Root volume size
k8s_instance_root_volume_size = 64

# Control-plane, ETCD, Worker
k8s_control_plane_node_count = 1
# ETCD, Worker
k8s_etcd_node_count = 1
# Worker
k8s_worker_node_count = 1

# Rancher Import Configuration

# Security group CIDRs
network_cidr          = "10.0.0.0/16"   # Use your actual VPC CIDR
WIREGUARD_CIDR        = "10.13.13.0/24" # Use your actual WireGuard VPN CIDR
enable_rancher_import = false
# Rancher Import URL
rancher_import_url = "\"kubectl apply -f https://rancher.mosip.net/v3/import/dzshvnb6br7qtf267zsrr9xsw6tnb2vt4x68g79r2wzsnfgvkjq2jk_c-m-b5249w76.yaml\""
# DNS Records to map
subdomain_public   = ["resident", "prereg", "esignet", "healthservices", "signup"]
subdomain_internal = ["admin", "iam", "activemq", "kafka", "kibana", "postgres", "smtp", "pmp", "minio", "regclient", "compliance"]

# PostgreSQL Configuration (used when second EBS volume is enabled)
postgresql_version = "15"
storage_device     = "/dev/nvme2n1"
mount_point        = "/srv/postgres"
postgresql_port    = "5433"

# MOSIP Infrastructure Repository Configuration
mosip_infra_repo_url = "https://github.com/bhumi46/mosip-infra.git"

mosip_infra_branch = "develop"


# VPC Configuration - Existing VPC to use (discovered by Name tag)
vpc_name = "mosip-boxes"
