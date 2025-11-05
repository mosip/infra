# Environment name (infra component)
cluster_name = "<cluster_name>"
# MOSIP's domain (ex: sandbox.xyz.net)
cluster_env_domain = "<cluster_name>.xxxxx.net"
# Email-ID will be used by certbot to notify SSL certificate expiry via email
mosip_email_id = "<mosip_email_id>"
# SSH login key name for AWS node instances (ex: my-ssh-key)
ssh_key_name = "<ssh_key_name>"
# The AWS region for resource creation
aws_provider_region = "ap-south-1"

# Specific availability zones for VM deployment (optional)
# If empty, uses all available AZs in the region
# Example: ["ap-south-1a", "ap-south-1b"] for specific AZs
# Example: [] for all available AZs in the region
specific_availability_zones = []

# The instance type for Kubernetes nodes (control plane, worker, etcd)
k8s_instance_type = "t3a.2xlarge"
# The instance type for Nginx server (load balancer)
nginx_instance_type = "t3a.2xlarge"
# The Route 53 hosted zone ID
zone_id = "<route53_zone_id>"

## UBUNTU 24.04
# The Amazon Machine Image ID for the instances
ami = "ami-xxxxxxxxxxxx" # Ubuntu 24.04 LTS AMI ID for ap-south-1

# Repo K8S-INFRA URL
k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
# Repo K8S-INFRA branch
k8s_infra_branch = "v1.2.1.0"
# NGINX Node's Root volume size
nginx_node_root_volume_size = 24
# NGINX node's EBS volume size
nginx_node_ebs_volume_size = 300
# NGINX node's second EBS volume size (optional - set to 0 to disable)
nginx_node_ebs_volume_size_2 = 200 # Enable second EBS volume for PostgreSQL testing
# Kubernetes nodes Root volume size
k8s_instance_root_volume_size = 64

# Control-plane, ETCD, Worker
k8s_control_plane_node_count = 3
# ETCD, Worker
k8s_etcd_node_count = 3
# Worker
k8s_worker_node_count = 2

# RKE2 Version Configuration
rke2_version = "v1.28.9+rke2r1"

# Security group CIDRs
network_cidr   = "10.0.0.0/8" # Use your actual VPC CIDR
WIREGUARD_CIDR = "10.0.0.0/8" # Use your actual WireGuard VPN CIDR


# Rancher Import URL
# Rancher Import Configuration
enable_rancher_import = false
rancher_import_url    = "\"kubectl apply -f https://rancher.observation.mosip.net/v3/import/b94jcxqdddb9k9p7rj4kzf4c7xkkqnvrz886wx9pf44btvwjs5bnzt_c-m-flzdgnth.yaml\""
# DNS Records to map
subdomain_public   = ["resident", "prereg", "esignet", "healthservices", "signup"]
subdomain_internal = ["admin", "iam", "activemq", "kafka", "kibana", "postgres", "smtp", "pmp", "minio", "regclient", "compliance"]

# PostgreSQL Configuration (used when second EBS volume is enabled)
enable_postgresql_setup = true # Enable PostgreSQL setup for main infra
postgresql_version      = "15"
storage_device          = "/dev/nvme2n1"
mount_point             = "/srv/postgres"
postgresql_port         = "5433"

# MOSIP Infrastructure Repository Configuration
mosip_infra_repo_url = "https://github.com/mosip/infra.git"

mosip_infra_branch = "v0.1.0-beta.1"


# VPC Configuration - Existing VPC to use (discovered by Name tag)
vpc_name = "<vpc_name>"

v