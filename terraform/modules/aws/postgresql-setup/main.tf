# PostgreSQL Setup Module - Runs after RKE2 cluster is ready

variable "NGINX_PUBLIC_IP" { type = string }
variable "NGINX_PRIVATE_IP" { type = string }
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

  provisioner "local-exec" {
    command     = <<EOT
      set -euo pipefail

      # Set environment variables for the PostgreSQL setup script
      export POSTGRESQL_VERSION="${var.POSTGRESQL_VERSION}"
      export STORAGE_DEVICE="${var.STORAGE_DEVICE}"
      export MOUNT_POINT="${var.MOUNT_POINT}"
      export POSTGRESQL_PORT="${var.POSTGRESQL_PORT}"
      export NETWORK_CIDR="${var.NETWORK_CIDR}"
      export MOSIP_INFRA_REPO_URL="${var.MOSIP_INFRA_REPO_URL}"
      export MOSIP_INFRA_BRANCH="${var.MOSIP_INFRA_BRANCH}"

      export CONTROL_PLANE_HOST="${var.CONTROL_PLANE_HOST}"
      export CONTROL_PLANE_USER="${var.CONTROL_PLANE_USER}"

      # Override the IP since we're running locally
      export NGINX_NODE_IP_OVERRIDE="${var.NGINX_PRIVATE_IP}"

      # SECURITY: Provide the SSH key for ansible connection securely via env var
      # avoiding interpolation into the command string itself
      KEY_FILE=$(mktemp /tmp/postgres-ssh-key-XXXXXX)
      trap 'rm -f "$KEY_FILE"; unset SSH_PRIVATE_KEY_FILE' EXIT ERR INT
      chmod 600 "$KEY_FILE"
      printf '%s' "$TF_POSTGRES_SSH_KEY" > "$KEY_FILE"
      export SSH_PRIVATE_KEY_FILE="$KEY_FILE"

      # Skip Kubernetes deployment in script - Terraform will handle it
      export SKIP_K8S_DEPLOYMENT=true

      # Execute the PostgreSQL setup script locally
      chmod +x ${path.module}/postgresql-setup.sh
      bash ${path.module}/postgresql-setup.sh
      
      # Clean up SSH key
      rm -f "$KEY_FILE"
    EOT
    interpreter = ["bash", "-c"]
    environment = {
      TF_POSTGRES_SSH_KEY = var.SSH_PRIVATE_KEY
    }
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

  # Copy YAML files to control plane (already generated locally by Ansible)
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

      # Create postgres namespace if it doesn't exist
      "echo 'Creating postgres namespace...'",
      "kubectl create namespace postgres --dry-run=client -o yaml | kubectl apply -f -",

      # Deploy PostgreSQL resources
      "kubectl apply -f /tmp/postgres-postgresql.yml",
      "kubectl apply -f /tmp/postgres-setup-config.yml",
      "echo 'PostgreSQL Kubernetes resources deployed successfully!'",

      # Verify the resources were created
      "echo 'Verifying PostgreSQL resources...'",
      "kubectl get secret -n postgres postgres-postgresql || echo 'Secret not found'",
      "kubectl get configmap -n postgres postgres-setup-config || echo 'ConfigMap not found'",

      # Cleanup
      "rm -f /tmp/postgres-postgresql.yml /tmp/postgres-setup-config.yml"
    ]
  }

}
