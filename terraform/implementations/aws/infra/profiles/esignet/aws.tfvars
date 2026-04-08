# ============================================================
# eSignet Standalone Infrastructure Profile
# ============================================================
# Lightweight deployment for standalone eSignet
# Includes: eSignet, OIDC UI, Postgres, Redis, Kafka, Keycloak
# Does NOT include full MOSIP platform services
# ============================================================

# Environment name (infra component)
cluster_name = "ab11"

# eSignet's domain (ex: esignet.xyz.net)
cluster_env_domain = "ab11.mosip.net"

# Email-ID will be used by certbot to notify SSL certificate expiry via email
mosip_email_id = "abhisahu1920@gmail.com"

# SSH login key name for AWS node instances (ex: my-ssh-key)
ssh_key_name = "mosip-aws"

# The AWS region for resource creation
aws_provider_region = "ap-south-1"

# Specific availability zones for VM deployment (optional)
specific_availability_zones = ["ap-south-1b"]

# The instance type for Kubernetes nodes (control plane, worker, etcd)
# Smaller instance type since eSignet standalone needs fewer resources
k8s_instance_type = "t3a.xlarge"

# The instance type for Nginx server (load balancer)
nginx_instance_type = "t3a.xlarge"

# The Route 53 hosted zone ID
zone_id ="Z090954828SJIEL6P5406"

## UBUNTU 24.04
# The Amazon Machine Image ID for the instances
ami = "ami-0ad21ae1d0696ad58"

# Repo K8S-INFRA URL
k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"

# Repo K8S-INFRA branch
k8s_infra_branch = "release-1.2.1.x"

# NGINX Node's Root volume size
nginx_node_root_volume_size = 24

# NGINX node's EBS volume size
nginx_node_ebs_volume_size = 200

# NGINX node's second EBS volume size (set to 0 - not needed for standalone eSignet)
nginx_node_ebs_volume_size_2 = 200

# Kubernetes nodes Root volume size
k8s_instance_root_volume_size = 64

# Control-plane, ETCD, Worker — smaller cluster for standalone eSignet
k8s_control_plane_node_count = 1

# ETCD, Worker
k8s_etcd_node_count = 1

# Worker
k8s_worker_node_count = 2

# RKE2 Version Configuration
rke2_version = "v1.28.9+rke2r1"

# Security group CIDRs
network_cidr   = "172.0.0.0/8" # Use your actual VPC CIDR
WIREGUARD_CIDR = "172.0.0.0/8" # Use your actual WireGuard VPN CIDR

# Rancher Import Configuration
enable_rancher_import = true
rancher_import_url    = "\"kubectl apply -f https://rancher.mosip.net/v3/import/94mdxbtbb2vqf5kh6h6mjdcx49t7h9m2fdh5t7df78t9z7qk9nzm8p_c-m-2fk99m9b.yaml\""

# DNS Records to map — only eSignet-relevant subdomains
subdomain_public   = ["esignet", "signup", "minio"]
subdomain_internal = ["iam", "kafka", "postgres", "keycloak"]

# PostgreSQL Configuration
enable_postgresql_setup = true
postgresql_version      = "15"
storage_device          = "/dev/nvme2n1"
mount_point             = "/srv/postgres"
postgresql_port         = "5433"

# MOSIP Infrastructure Repository Configuration
mosip_infra_repo_url = "https://github.com/mosip/infra.git"

mosip_infra_branch = "release-0.2.0"

# VPC Configuration - Existing VPC to use (discovered by Name tag)
vpc_name = "default"

# ── ActiveMQ Configuration ─────────────────────────────────────────────────────
# Set enable_activemq_setup = true AND nginx_node_ebs_volume_size_3 > 0 to
# create a dedicated EBS volume, format it as XFS, and mount it on the NGINX node.
# ActiveMQ itself runs inside Kubernetes via Helm (no software installed here).
# Both conditions must be true — set either to false/0 to skip entirely.
enable_activemq_setup        = false # Toggle: true = create & mount, false = skip
nginx_node_ebs_volume_size_3 = 0     # Volume size in GB (e.g. 100); 0 = disabled

activemq_storage_device    = "/dev/nvme3n1"
activemq_mount_point       = "/srv/activemq"
activemq_nfs_allowed_hosts = "*" # Restrict to cluster CIDR in production e.g. "10.0.0.0/8"
