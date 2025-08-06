# Environment name (ex: sandbox)
cluster_name = "testvpc"
# MOSIP's domain (ex: sandbox.xyz.net)
cluster_env_domain = "testvpc.mosip.net"
# Email-ID will be used by certbot to notify SSL certificate expiry via email
mosip_email_id = "chandra.mishra@technoforte.co.in"
# SSH login key name for AWS node instances (ex: my-ssh-key)
ssh_key_name = "mosip-aws"
# The AWS region for resource creation
aws_provider_region = "ap-south-1"
# The instance type for Kubernetes nodes
k8s_instance_type = "t3a.2xlarge"
# The instance type for Nginx server
nginx_instance_type = "t3a.2xlarge"
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
# Kubernetes nodes Root volume size
k8s_instance_root_volume_size = 64

# Control-plane, ETCD, Worker
k8s_control_plane_node_count = 3
# ETCD, Worker
k8s_etcd_node_count = 3
# Worker
k8s_worker_node_count = 2

# Rancher Import Configuration
enable_rancher_import = false
# Rancher Import URL
rancher_import_url = "\"kubectl apply -f https://rancher.mosip.net/v3/import/dzshvnb6br7qtf267zsrr9xsw6tnb2vt4x68g79r2wzsnfgvkjq2jk_c-m-b5249w76.yaml\""
# DNS Records to map
subdomain_public   = ["resident", "prereg", "esignet", "healthservices", "signup"]
subdomain_internal = ["admin", "iam", "activemq", "kafka", "kibana", "postgres", "smtp", "pmp", "minio", "regclient", "compliance"]

# VPC Configuration - Existing VPC to use (discovered by Name tag)
vpc_name = "mosip-boxes"

# SSH Private Key (should be set via environment variable or terraform.tfvars)
# ssh_private_key = "your-private-key-content"
