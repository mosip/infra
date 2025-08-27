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

      # Skip Kubernetes deployment in script - Terraform will handle it
      "export SKIP_K8S_DEPLOYMENT=true",

      # Execute the PostgreSQL setup script (PostgreSQL install + YAML generation only)
      "sudo chmod +x /tmp/postgresql-setup.sh",
      "bash /tmp/postgresql-setup.sh"
    ]
  }
}

# Separate resource for Kubernetes deployment via control plane
resource "null_resource" "postgresql-k8s-deployment" {
  count      = var.NGINX_NODE_EBS_VOLUME_SIZE_2 > 0 ? 1 : 0
  depends_on = [null_resource.PostgreSQL-ansible-setup]

  connection {
    type        = "ssh"
    host        = var.CONTROL_PLANE_HOST
    user        = var.CONTROL_PLANE_USER
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "10m"
    agent       = false
  }

  # Copy PostgreSQL secrets from nginx node to control plane
  provisioner "local-exec" {
    command = <<EOF
echo "${var.SSH_PRIVATE_KEY}" > /tmp/nginx-key
chmod 600 /tmp/nginx-key

# Create local directory and download YAML files from nginx node
mkdir -p /tmp/postgresql-secrets
scp -i /tmp/nginx-key -o StrictHostKeyChecking=no ubuntu@${var.NGINX_PUBLIC_IP}:/tmp/postgresql-secrets/*.yml /tmp/postgresql-secrets/

# Clean up nginx key
rm -f /tmp/nginx-key
EOF
  }

  # Copy YAML files to control plane
  provisioner "file" {
    source      = "/tmp/postgresql-secrets/postgres-postgresql.yml"
    destination = "/tmp/postgres-postgresql.yml"
  }

  provisioner "file" {
    source      = "/tmp/postgresql-secrets/postgres-setup-config.yml"
    destination = "/tmp/postgres-setup-config.yml"
  }

  # Deploy to Kubernetes
  provisioner "remote-exec" {
    inline = [
      # Set up kubeconfig for kubectl (RKE2 creates node-specific kubeconfig files)
      "export KUBECONFIG=$(find /home/ubuntu/.kube/ -name '*.yaml' | head -1)",
      "echo 'Using kubeconfig: $KUBECONFIG'",
      
      # Verify kubectl connectivity
      "kubectl cluster-info",
      
      # Deploy PostgreSQL resources
      "kubectl apply -f /tmp/postgres-postgresql.yml",
      "kubectl apply -f /tmp/postgres-setup-config.yml",
      "echo 'PostgreSQL Kubernetes resources deployed successfully!'",
      
      # Cleanup
      "rm -f /tmp/postgres-postgresql.yml /tmp/postgres-setup-config.yml"
    ]
  }

  # Cleanup local files
  provisioner "local-exec" {
    command = "rm -rf /tmp/postgresql-secrets"
  }
}
