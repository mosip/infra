# AWS Observability Infrastructure Configuration (Minimal Resources)
# Uses the same modules as infra but with smaller instances and minimal resources

# Cloud provider
cloud_provider = "aws"

# Environment name (observability cluster)
cluster_name = "testvpc-observ"

# MOSIP domain
cluster_env_domain = "observ.mosip.net"

# Email-ID for SSL certificate notifications
mosip_email_id = "chandra.mishra@technoforte.co.in"

# SSH key name for AWS instances
ssh_key_name = "mosip-aws"

# AWS region
aws_provider_region = "ap-south-1"

# Minimal node counts for observability
k8s_control_plane_node_count = 1
k8s_etcd_node_count          = 0
k8s_worker_node_count        = 0

# Minimal instance types for observability (upgraded for better performance)
k8s_instance_type   = "t3a.2xlarge"
nginx_instance_type = "t3a.large"

# AMI ID (Ubuntu 24.04 LTS in ap-south-1)
ami = "ami-0ad21ae1d0696ad58"

# Route53 zone ID for DNS records
zone_id = "Z090954828SJIEL6P5406"

# VPC name (should match the one created by base-infra)
vpc_name = "mosip-boxes"

# Minimal storage configuration
nginx_node_root_volume_size   = 20  # Smaller than infra (24)
nginx_node_ebs_volume_size    = 100 # Smaller than infra (300)
k8s_instance_root_volume_size = 32  # Smaller than infra (64)

# Subdomains for observability services
subdomain_public = []

subdomain_internal = [
  "rancher",
  "keycloak"
]

# Repository configuration
k8s_infra_repo_url = "https://github.com/bhumi46/k8s-infra.git"
k8s_infra_branch   = "develop"

# Rancher UI configuration (hostname will be dynamically created from cluster_env_domain)
rancher_hostname           = "rancher.observ.mosip.net" # Will default to rancher.testvpc.mosip.net
rancher_bootstrap_password = "admin"

# Keycloak configuration (hostname will be dynamically created from cluster_env_domain)  
keycloak_hostname = "keycloak.observ.mosip.net" # Will default to iam.testvpc.mosip.net

# Enable Rancher-Keycloak integration for observability cluster
enable_rancher_keycloak_integration = true

# Rancher import (same as infra)
enable_rancher_import = false
rancher_import_url    = "\"kubectl apply -f https://rancher.mosip.net/v3/import/dzshvnb6br7qtf267zsrr9xsw6tnb2vt4x68g79r2wzsnfgvkjq2jk_c-m-b5249w76.yaml\""
