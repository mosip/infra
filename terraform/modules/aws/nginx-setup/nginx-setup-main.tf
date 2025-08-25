variable "NGINX_PUBLIC_IP" { type = string }
variable "CLUSTER_ENV_DOMAIN" { type = string }
variable "MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST" { type = string }
variable "MOSIP_PUBLIC_DOMAIN_LIST" { type = string }
variable "CERTBOT_EMAIL" { type = string }
variable "SSH_PRIVATE_KEY" { type = string }
variable "K8S_INFRA_REPO_URL" {
  description = "The URL of the Kubernetes infrastructure GitHub repository"
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/.+/.+\\.git$", var.K8S_INFRA_REPO_URL))
    error_message = "The K8S_INFRA_REPO_URL must be a valid GitHub repository URL ending with .git"
  }
}

variable "K8S_INFRA_BRANCH" {
  type    = string
  default = "develop"
}

# PostgreSQL Configuration Variables
variable "NGINX_NODE_EBS_VOLUME_SIZE_2" { type = number }
variable "POSTGRESQL_VERSION" {
  type        = string
  default     = "15"
  description = "PostgreSQL version to install"
}
variable "STORAGE_DEVICE" {
  type        = string
  default     = "/dev/nvme2n1"
  description = "Storage device path for PostgreSQL data"
}
variable "MOUNT_POINT" {
  type        = string
  default     = "/srv/postgres"
  description = "Mount point for PostgreSQL data directory"
}
variable "POSTGRESQL_PORT" {
  type        = string
  default     = "5433"
  description = "PostgreSQL port configuration"
}
variable "NETWORK_CIDR" {
  type        = string
  description = "VPC CIDR block for internal communication"
}

# MOSIP Infrastructure Repository Configuration
variable "MOSIP_INFRA_REPO_URL" {
  description = "The URL of the MOSIP infrastructure GitHub repository"
  type        = string
  validation {
    condition     = can(regex("^https://github\\.com/.+/.+\\.git$", var.MOSIP_INFRA_REPO_URL))
    error_message = "The MOSIP_INFRA_REPO_URL must be a valid GitHub repository URL ending with .git"
  }
}

variable "MOSIP_INFRA_BRANCH" {
  type    = string
  default = "develop"
}

# Kubernetes Control Plane Configuration for PostgreSQL deployment
variable "CONTROL_PLANE_HOST" {
  type        = string
  description = "IP address or hostname of the Kubernetes control plane node where kubectl is configured"

  # Example: In your main Terraform configuration, pass the control plane IP:
  # CONTROL_PLANE_HOST = module.k8s_cluster.control_plane_private_ip
  # or
  # CONTROL_PLANE_HOST = "10.0.1.10"
}

variable "CONTROL_PLANE_USER" {
  type        = string
  default     = "ubuntu"
  description = "Username for SSH access to the control plane node"
}

locals {
  NGINX_CONFIG = {
    cluster_env_domain                = var.CLUSTER_ENV_DOMAIN
    env_var_file                      = "/etc/environment"
    cluster_nginx_certs               = "/etc/letsencrypt/live/${var.CLUSTER_ENV_DOMAIN}/fullchain.pem"
    cluster_nginx_cert_key            = "/etc/letsencrypt/live/${var.CLUSTER_ENV_DOMAIN}/privkey.pem"
    cluster_node_ips                  = var.MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST
    cluster_public_domains            = var.MOSIP_PUBLIC_DOMAIN_LIST
    cluster_ingress_public_nodeport   = "30080"
    cluster_ingress_internal_nodeport = "31080"
    cluster_ingress_postgres_nodeport = "31432"
    cluster_ingress_minio_nodeport    = "30900"
    cluster_ingress_activemq_nodeport = "31616"
    certbot_email                     = var.CERTBOT_EMAIL
    k8s_infra_repo_url                = var.K8S_INFRA_REPO_URL
    k8s_infra_branch                  = var.K8S_INFRA_BRANCH
    working_dir                       = "/home/ubuntu/"
    nginx_location                    = "./k8s-infra/nginx/mosip/"
  }

  nginx_env_vars = [
    for key, value in local.NGINX_CONFIG :
    "echo 'export ${key}=${value}' | sudo tee -a ${local.NGINX_CONFIG.env_var_file}"
  ]
}

resource "null_resource" "Nginx-setup" {
  triggers = {
    # node_count_or_hash = module.ec2-resource-creation.node_count
    # or if you used hash:
    # node_hash       = md5(var.MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST)
    # public_dns_hash = md5(var.MOSIP_PUBLIC_DOMAIN_LIST)
  }

  connection {
    type        = "ssh"
    host        = var.NGINX_PUBLIC_IP
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
    timeout     = "5m"                # 5 minute timeout
    agent       = false               # Don't use SSH agent
  }

  provisioner "file" {
    source      = "${path.module}/nginx-setup.sh"
    destination = "/tmp/nginx-setup.sh"
  }

  provisioner "remote-exec" {
    inline = concat(
      local.nginx_env_vars,
      ["source /etc/environment",
        "echo \"export cluster_nginx_internal_ip=\"$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/local-ipv4)\"\" | sudo tee -a ${local.NGINX_CONFIG.env_var_file}",
        "echo \"export cluster_nginx_public_ip=\"$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/local-ipv4)\"\" | sudo tee -a ${local.NGINX_CONFIG.env_var_file}",
        "sudo chmod +x /tmp/nginx-setup.sh",
        "sudo bash /tmp/nginx-setup.sh"
      ]
    )
  }
}

# PostgreSQL Ansible Setup (conditional on second EBS volume)
resource "null_resource" "PostgreSQL-ansible-setup" {
  count = var.NGINX_NODE_EBS_VOLUME_SIZE_2 > 0 ? 1 : 0

  depends_on = [null_resource.Nginx-setup]

  triggers = {
    postgresql_config_hash = md5(join("", [
      var.POSTGRESQL_VERSION,
      var.STORAGE_DEVICE,
      var.MOUNT_POINT,
      var.POSTGRESQL_PORT,
      var.MOSIP_INFRA_REPO_URL,
      var.MOSIP_INFRA_BRANCH
    ]))
  }

  connection {
    type        = "ssh"
    host        = var.NGINX_PUBLIC_IP
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "15m" # Fast timeout for PostgreSQL setup
    agent       = false
  }

  provisioner "file" {
    source      = "${path.module}/postgresql-setup.sh"
    destination = "/tmp/postgresql-setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      # Set environment variables for the PostgreSQL setup script
      "export POSTGRESQL_VERSION=${var.POSTGRESQL_VERSION}",
      "export STORAGE_DEVICE=${var.STORAGE_DEVICE}",
      "export MOUNT_POINT=${var.MOUNT_POINT}",
      "export POSTGRESQL_PORT=${var.POSTGRESQL_PORT}",
      "export NETWORK_CIDR=${var.NETWORK_CIDR}",
      "export MOSIP_INFRA_REPO_URL=${var.MOSIP_INFRA_REPO_URL}",
      "export MOSIP_INFRA_BRANCH=${var.MOSIP_INFRA_BRANCH}",

      # Set control plane variables for Kubernetes deployment
      "export CONTROL_PLANE_HOST=${var.CONTROL_PLANE_HOST}",
      "export CONTROL_PLANE_USER=${var.CONTROL_PLANE_USER}",

      # Execute the PostgreSQL setup script
      "sudo chmod +x /tmp/postgresql-setup.sh",
      "bash /tmp/postgresql-setup.sh"
    ]
  }
}
