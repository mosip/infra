# PostgreSQL Setup Module - Runs after RKE2 cluster is ready

variable "NGINX_PUBLIC_IP" { type = string }
variable "SSH_PRIVATE_KEY" { type = string }
variable "NGINX_NODE_EBS_VOLUME_SIZE_2" { type = number }

# PostgreSQL Configuration Variables
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
  type        = string
  description = "The URL of the MOSIP infrastructure GitHub repository"
}
variable "MOSIP_INFRA_BRANCH" {
  type        = string
  default     = "develop"
  description = "The branch of the MOSIP infrastructure repository"
}

# Kubernetes Control Plane Configuration for PostgreSQL deployment
variable "CONTROL_PLANE_HOST" {
  type        = string
  description = "IP address of the Kubernetes control plane node"
}
variable "CONTROL_PLANE_USER" {
  type        = string
  default     = "ubuntu"
  description = "SSH username for control plane access"
}

# PostgreSQL Ansible Setup (conditional on second EBS volume)
resource "null_resource" "PostgreSQL-ansible-setup" {
  count = var.NGINX_NODE_EBS_VOLUME_SIZE_2 > 0 ? 1 : 0

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
      
      # Set SSH private key for nginx->control plane communication
      "export SSH_PRIVATE_KEY='${var.SSH_PRIVATE_KEY}'",

      # Execute the PostgreSQL setup script
      "sudo chmod +x /tmp/postgresql-setup.sh",
      "bash /tmp/postgresql-setup.sh"
    ]
  }
}
