# AWS Observability Infrastructure Configuration (Minimal Resources)
# Uses the same modules as infra but with smaller instances and minimal resources

# Cloud provider
cloud_provider = "aws"

# Environment name (observability component)
cluster_name = "<cluster-name>"

# MOSIP domain
cluster_env_domain = "<cluster-env-domain>"

# Email-ID for SSL certificate notifications
mosip_email_id = "<email-id>"

# SSH key name for AWS instances
ssh_key_name = "<ssh-key-name>"

# AWS region
aws_provider_region = "ap-south-1"

# Specific availability zones for observation VM deployment (optional)
# If empty, uses all available AZs in the region
# Example: ["ap-south-1a", "ap-south-1b"] for specific AZs
# Example: [] for all available AZs in the region
specific_availability_zones = []

# Minimal node counts for observability
k8s_control_plane_node_count = 1
k8s_etcd_node_count          = 0
k8s_worker_node_count        = 1

# Minimal instance types for observability
k8s_instance_type   = "t3a.2xlarge"
nginx_instance_type = "t3a.large"

# AMI ID (Ubuntu 24.04 LTS in ap-south-1)
ami = "ami-0ad21ae1d0696ad58"

# Route53 zone ID for DNS records
zone_id = "<zone-id>"

# VPC name (should match the one created by base-infra)
vpc_name = "<vpc-name>"

# Minimal storage configuration
nginx_node_root_volume_size = 24 # Smaller than infra (24)
nginx_node_ebs_volume_size  = 64 # Smaller than infra (300)
# Second EBS volume for PostgreSQL (disabled for observ-infra)
nginx_node_ebs_volume_size_2  = 0  # Disabled for observability infrastructure
k8s_instance_root_volume_size = 32 # Smaller than infra (64)

# Subdomains for observability services
subdomain_public = []

subdomain_internal = [
  "rancher",
  "iam"
]

# Repository configuration
k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
k8s_infra_branch   = "v1.2.1.0"

# RKE2 Version Configuration
rke2_version = "v1.28.9+rke2r1"

# RKE2 Version Configuration
rke2_version = "v1.28.9+rke2r1"

# Rancher UI configuration (hostname will be dynamically created from cluster_env_domain)
rancher_hostname           = "rancher.<cluster-env-domain>" # example rancher.sandbox.xyz.net
rancher_bootstrap_password = "admin"
rancher_ui_version         = "2.8.3" # Rancher Helm chart version (avoid 2.8.3 due to CVEs)
# Keycloak configuration (hostname will be dynamically created from cluster_env_domain)  
keycloak_hostname = "iam.<cluster-env-domain>" # example iam.sandbox.xyz.net
# Enable Rancher-Keycloak integration for observability cluster
enable_rancher_keycloak_integration = true

# Rancher import (same as infra)
enable_rancher_import = false #dont enable for observ infra
rancher_import_url    = "\"<rancher-import-url>\"" #dont update for observ infra

# Security group CIDRs
network_cidr   = "10.0.0.0/8" # Use your actual VPC CIDR
WIREGUARD_CIDR = "10.0.0.0/8" # Use your actual WireGuard VPN CIDR

# PostgreSQL Configuration (used when second EBS volume is enabled)
postgresql_version = "15"
storage_device     = "/dev/nvme2n1"
mount_point        = "/srv/postgres"
postgresql_port    = "5433"

# MOSIP Infrastructure Repository Configuration
mosip_infra_repo_url = "https://github.com/mosip/mosip-infra.git"
mosip_infra_branch   = "v0.1.0"
