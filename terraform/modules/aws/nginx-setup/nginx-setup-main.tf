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
  default = "main"
}

# PostgreSQL Configuration Variables
variable "NGINX_NODE_EBS_VOLUME_SIZE_2" { type = number }
variable "POSTGRESQL_VERSION" { type = string }
variable "STORAGE_DEVICE" { type = string }
variable "MOUNT_POINT" { type = string }
variable "POSTGRESQL_PORT" { type = string }
variable "NETWORK_CIDR" { type = string }

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
  default = "main"
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
      var.MOSIP_INFRA_REPO_URL
    ]))
  }

  connection {
    type        = "ssh"
    host        = var.NGINX_PUBLIC_IP
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "15m"  # Increased timeout for PostgreSQL setup
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      # Set up logging and error handling
      "set -e",  # Exit on error
      "exec > /tmp/postgresql-setup.log 2>&1",  # Simplified logging - redirect both stdout and stderr
      "echo '=== PostgreSQL Ansible Setup Started at $(date) ==='",
      
      # Install prerequisites with timeout
      "echo '=== Installing Prerequisites ==='",
      "sudo apt-get update -qq",
      "timeout 300 sudo apt-get install -y git ansible python3-pip",
      
      # Clone MOSIP infrastructure repository
      "echo '=== Cloning Repository ==='",
      "cd /tmp",
      "rm -rf mosip-infra",
      "timeout 300 git clone ${var.MOSIP_INFRA_REPO_URL}",
      "cd mosip-infra",
      "git checkout ${var.MOSIP_INFRA_BRANCH}",
      
      # Navigate to PostgreSQL Ansible directory
      "echo '=== Navigating to PostgreSQL Ansible ==='",
      "cd deployment/v3/external/postgres/ansible",
      "pwd && ls -la",
      
      # Create dynamic inventory with current host
      "echo '=== Creating Inventory ==='",
      "echo '[postgresql_servers]' > inventory.ini",  # Fixed: changed from 'postgres' to 'postgresql_servers'
      "echo \"localhost ansible_connection=local ansible_user=ubuntu ansible_become=yes ansible_become_method=sudo\" >> inventory.ini",
      "cat inventory.ini",
      
      # Set PostgreSQL configuration variables
      "echo '=== Setting Environment Variables ==='",
      "export POSTGRESQL_VERSION=${var.POSTGRESQL_VERSION}",
      "export STORAGE_DEVICE=${var.STORAGE_DEVICE}",
      "export MOUNT_POINT=${var.MOUNT_POINT}",
      "export POSTGRESQL_PORT=${var.POSTGRESQL_PORT}",
      "export NETWORK_CIDR=${var.NETWORK_CIDR}",
      "export DEBIAN_FRONTEND=noninteractive",  # Prevent interactive prompts
      "export ANSIBLE_HOST_KEY_CHECKING=False",  # Skip host key checking
      "export ANSIBLE_STDOUT_CALLBACK=debug",   # Verbose output
      "export ANSIBLE_TIMEOUT=30",              # Set ansible timeout
      "export ANSIBLE_CONNECT_TIMEOUT=30",      # Set connection timeout
      
      # Configure APT to prevent hanging
      "echo '=== Configuring APT for non-interactive mode ==='",
      "sudo mkdir -p /etc/apt/apt.conf.d/",
      "echo 'APT::Get::Assume-Yes \"true\";' | sudo tee /etc/apt/apt.conf.d/99automated",
      "echo 'APT::Get::force-yes \"true\";' | sudo tee -a /etc/apt/apt.conf.d/99automated",
      "echo 'Dpkg::Options { \"--force-confdef\"; \"--force-confold\"; }' | sudo tee -a /etc/apt/apt.conf.d/99automated",
      
      # Check if storage device exists and wait if needed
      "echo '=== Checking Storage Device ==='",
      "echo 'Waiting for storage device ${var.STORAGE_DEVICE}...'",
      "for i in {1..60}; do if [ -b ${var.STORAGE_DEVICE} ]; then echo 'Storage device found!'; break; fi; echo \"Attempt $i: waiting for ${var.STORAGE_DEVICE}...\"; sleep 5; done",
      "if [ ! -b ${var.STORAGE_DEVICE} ]; then echo 'ERROR: Storage device ${var.STORAGE_DEVICE} not found after 5 minutes'; lsblk; exit 1; fi",
      "lsblk | grep -E '(nvme|xvd|sd)' || true",
      
      # Run PostgreSQL setup with timeout and error handling
      "echo '=== Running PostgreSQL Ansible Playbook ==='",
      "timeout 1800 ansible-playbook -vvv -i inventory.ini -e postgresql_version=$POSTGRESQL_VERSION -e storage_device=$STORAGE_DEVICE -e mount_point=$MOUNT_POINT -e postgresql_port=$POSTGRESQL_PORT -e network_cidr=$NETWORK_CIDR postgresql-setup.yml || (echo 'Ansible playbook failed with exit code $?'; cat /tmp/postgresql-setup.log; exit 1)",
      
      # Verify PostgreSQL installation
      "echo '=== Verifying PostgreSQL Installation ==='",
      "sleep 10",  # Wait for service to start
      "sudo systemctl status postgresql --no-pager || true",
      "sudo systemctl is-active postgresql || true",
      "sudo -u postgres psql -p ${var.POSTGRESQL_PORT} -c 'SELECT version();' || echo 'PostgreSQL verification failed'",
      
      "echo '=== PostgreSQL Ansible Setup Completed at $(date) ==='",
      "echo '=== Setup Log saved to /tmp/postgresql-setup.log ==='",
      "echo '=== Displaying last 20 lines of log for verification ==='",
      "tail -20 /tmp/postgresql-setup.log || true"
    ]
  }
}
