cloud_provider = "aws"
# Environment name (ex: sandbox)
CLUSTER_NAME = "cellbox21"
# MOSIP's domain (ex: sandbox.xyz.net)
CLUSTER_ENV_DOMAIN = "cellbox21.mosip.net"
# Email-ID will be used by certbot to notify SSL certificate expiry via email
MOSIP_EMAIL_ID = "chandra.mishra@technoforte.co.in"
# SSH login key name for AWS node instances (ex: my-ssh-key)
SSH_KEY_NAME = "mosip-aws"
# The AWS region for resource creation
AWS_PROVIDER_REGION = "ap-south-1"
# The instance type for Kubernetes nodes
K8S_INSTANCE_TYPE = "t3a.2xlarge"
# The instance type for Nginx server
NGINX_INSTANCE_TYPE = "t3a.2xlarge"
# The Route 53 hosted zone ID
ZONE_ID = "Z090954828SJIEL6P5406"

## UBUNTU 24.04
# The Amazon Machine Image ID for the instances
AMI = "ami-0ad21ae1d0696ad58"

# Repo K8S-INFRA URL
K8S_INFRA_REPO_URL = "https://github.com/mosip/k8s-infra.git"
# Repo K8S-INFRA branch
K8S_INFRA_BRANCH = "develop"
# NGINX Node's Root volume size
NGINX_NODE_ROOT_VOLUME_SIZE = "24"
# NGINX node's EBS volume size
NGINX_NODE_EBS_VOLUME_SIZE = "300"
# Kubernetes nodes Root volume size
K8S_INSTANCE_ROOT_VOLUME_SIZE = "64"

# Control-plane, ETCD, Worker
K8S_CONTROL_PLANE_NODE_COUNT = 3
# ETCD, Worker
K8S_ETCD_NODE_COUNT = 5
# Worker
K8S_WORKER_NODE_COUNT = 8

# Rancher Import URL
RANCHER_IMPORT_URL = "\"kubectl apply -f https://rancher.mosip.net/v3/import/bxgt7vt55gtl7xcwzwwnkl4hs89cwkkrt662ml52zsh79t2fp9zrtn_c-m-sf8jpj44.yaml\""
# DNS Records to map
SUBDOMAIN_PUBLIC   = ["resident", "prereg", "esignet", "healthservices", "signup"]
SUBDOMAIN_INTERNAL = ["admin", "iam", "activemq", "kafka", "kibana", "postgres", "smtp", "pmp", "minio", "regclient", "compliance"]
