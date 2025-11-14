variable "NGINX_PUBLIC_IP" { type = string }
variable "NGINX_PRIVATE_IP" { type = string }
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
  default = "main"
}

variable "NGINX_TYPE" {
  description = "Type of NGINX setup: 'mosip' or 'observability'"
  type        = string
  default     = "mosip"

  validation {
    condition     = contains(["mosip", "observability"], var.NGINX_TYPE)
    error_message = "NGINX_TYPE must be either 'mosip' or 'observability'"
  }
}

locals {
  # Base configuration for MOSIP
  mosip_config = {
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

  # Configuration for Observability
  observability_config = {
    cluster_env_domain            = var.CLUSTER_ENV_DOMAIN
    observation_nginx_certs       = "/etc/letsencrypt/live/${var.CLUSTER_ENV_DOMAIN}/fullchain.pem"
    observation_nginx_cert_key    = "/etc/letsencrypt/live/${var.CLUSTER_ENV_DOMAIN}/privkey.pem"
    observation_cluster_node_ips  = var.MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST
    observation_ingress_nodeport  = "30080"
    certbot_email                 = var.CERTBOT_EMAIL
    env_var_file                  = "/etc/environment"
    k8s_infra_repo_url            = var.K8S_INFRA_REPO_URL
    k8s_infra_branch              = var.K8S_INFRA_BRANCH
    working_dir                   = "/home/ubuntu/"
    nginx_location                = "./k8s-infra/nginx/observation/"
  }

  # Select configuration based on NGINX_TYPE
  NGINX_CONFIG = var.NGINX_TYPE == "mosip" ? local.mosip_config : local.observability_config

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
    host        = var.NGINX_PRIVATE_IP # Use private IP - works through WireGuard
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "10m"
    agent       = false
  }
  provisioner "file" {
    source      = "${path.module}/nginx-setup.sh"
    destination = "/tmp/nginx-setup.sh"
  }
  provisioner "remote-exec" {
    inline = concat(
      local.nginx_env_vars,
      var.NGINX_TYPE == "mosip" ? [
        "source /etc/environment",
        "echo \"export cluster_nginx_internal_ip=$(curl -s -H 'X-aws-ec2-metadata-token: '$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600') http://169.254.169.254/latest/meta-data/local-ipv4)\" | sudo tee -a ${local.NGINX_CONFIG.env_var_file}",
        "echo \"export cluster_nginx_public_ip=$(curl -s -H 'X-aws-ec2-metadata-token: '$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600') http://169.254.169.254/latest/meta-data/public-ipv4)\" | sudo tee -a ${local.NGINX_CONFIG.env_var_file}",
        "sudo chmod +x /tmp/nginx-setup.sh",
        "sudo bash /tmp/nginx-setup.sh"
      ] : [
        "source /etc/environment",
        "echo \"export observation_nginx_ip=$(curl -s -H 'X-aws-ec2-metadata-token: '$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600') http://169.254.169.254/latest/meta-data/local-ipv4)\" | sudo tee -a ${local.NGINX_CONFIG.env_var_file}",
        "sudo chmod +x /tmp/nginx-setup.sh",
        "sudo bash /tmp/nginx-setup.sh"
      ]
    )
  }
}
