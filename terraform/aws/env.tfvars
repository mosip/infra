# Environment name (ex: sandbox)
CLUSTER_NAME = ""
# MOSIP's domain (ex: sandbox.xyz.net)
MOSIP_DOMAIN = ""
# Email-ID will be used by certbot to notify SSL certificate expiry via email
MOSIP_EMAIL_ID = ""
# SSH login key name for AWS node instances (ex: my-ssh-key)
SSH_KEY_NAME = ""
# The AWS region for resource creation
AWS_PROVIDER_REGION = ""
# The instance type for Kubernetes nodes
K8S_INSTANCE_TYPE = ""
# The instance type for Nginx server
NGINX_INSTANCE_TYPE = ""
# The Route 53 hosted zone ID
ZONE_ID = ""
## UBUNTU 20.04
#AMI                 = "ami-0a7cf821b91bcccbc"
## UBUNTU 24.04
# The Amazon Machine Image ID for the instances
AMI = "ami-0ad21ae1d0696ad58"

# Repo K8S-INFRA URL
K8S_INFRA_REPO_URL = "https://github.com/mosip/k8s-infra.git"
# Repo K8S-INFRA branch
K8S_INFRA_BRANCH = "develop"
# NGINX Node's Root volume size
NGINX_NODE_ROOT_VOLUME_SIZE = "30"
# NGINX node's EBS volume size
NGINX_NODE_EBS_VOLUME_SIZE = "300"
# Kubernetes nodes Root volume size
K8S_INSTANCE_ROOT_VOLUME_SIZE = "50"

# Control-plane, ETCD, Worker
K8S_CONTROL_PLANE_NODE_COUNT = 4
# ETCD, Worker
K8S_ETCD_NODE_COUNT = 2
# Worker
K8S_WORKER_NODE_COUNT = 2

# Rancher Import URL
RANCHER_IMPORT_URL = "\"\""
