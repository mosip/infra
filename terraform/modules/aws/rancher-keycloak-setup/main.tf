terraform {
  required_version = ">= 1.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# Wait for NFS setup to complete
resource "null_resource" "wait_for_nfs" {
  provisioner "local-exec" {
    command = "sleep 30" # Wait for NFS to be ready
  }
}

# Verify Ansible is installed, install if not present
resource "null_resource" "verify_ansible" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [null_resource.wait_for_nfs]

  provisioner "local-exec" {
    command = <<-EOT
      if ! command -v ansible-playbook &> /dev/null; then
        echo "Ansible not found, installing..."
        if command -v pip3 &> /dev/null; then
          pip3 install ansible
        elif command -v pip &> /dev/null; then
          pip install ansible
        elif command -v apt-get &> /dev/null; then
          sudo apt-get update && sudo apt-get install -y ansible
        elif command -v yum &> /dev/null; then
          sudo yum install -y ansible
        else
          echo "ERROR: Could not install Ansible. Please install manually: pip install ansible"
          exit 1
        fi
      else
        echo "Ansible is already installed: $(ansible-playbook --version | head -1)"
      fi
    EOT
  }
}

# Create SSH private key file for Ansible
resource "local_file" "ssh_private_key" {
  count           = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on      = [null_resource.verify_ansible]
  content         = var.SSH_PRIVATE_KEY
  filename        = "${path.module}/ansible/.ssh_key"
  file_permission = "0600"
}

# Create Ansible inventory file
resource "local_file" "ansible_inventory" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [local_file.ssh_private_key]
  content = templatefile("${path.module}/ansible/inventory.tpl", {
    control_plane_ip = var.CONTROL_PLANE_IPS[0]
    ssh_key_file     = abspath(local_file.ssh_private_key[0].filename)
  })
  filename = "${path.module}/ansible/inventory.ini"
}

# Install Rancher UI using Ansible
resource "null_resource" "install_rancher" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [local_file.ansible_inventory]

  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i ${path.module}/ansible/inventory.ini \
        ${path.module}/ansible/install-rancher.yml \
        -e cluster_name='${var.CLUSTER_NAME}' \
        -e rancher_hostname_var='${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"}' \
        -e rancher_password='${var.RANCHER_BOOTSTRAP_PASSWORD}'
    EOT
  }

  triggers = {
    rancher_hostname = var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"
    cluster_name     = var.CLUSTER_NAME
  }
}

# Install Keycloak using Ansible
resource "null_resource" "install_keycloak" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [null_resource.install_rancher]

  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i ${path.module}/ansible/inventory.ini \
        ${path.module}/ansible/install-keycloak.yml \
        -e cluster_name='${var.CLUSTER_NAME}' \
        -e keycloak_hostname_var='${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}' \
        -e k8s_infra_repo_url='${var.K8S_INFRA_REPO_URL}' \
        -e k8s_infra_branch_name='${var.K8S_INFRA_BRANCH}'
    EOT
  }

  triggers = {
    keycloak_hostname = var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"
    k8s_infra_repo    = var.K8S_INFRA_REPO_URL
    k8s_infra_branch  = var.K8S_INFRA_BRANCH
    cluster_name      = var.CLUSTER_NAME
  }
}

# Get Rancher URL and status
resource "null_resource" "get_rancher_info" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [null_resource.install_rancher]

  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i ${path.module}/ansible/inventory.ini \
        ${path.module}/ansible/get-rancher-info.yml \
        -e cluster_name='${var.CLUSTER_NAME}' \
        -e rancher_hostname_var='${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"}' \
        -e rancher_password='${var.RANCHER_BOOTSTRAP_PASSWORD}'
    EOT
  }
}

# Get Keycloak URL and status
resource "null_resource" "get_keycloak_info" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [null_resource.install_keycloak]

  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i ${path.module}/ansible/inventory.ini \
        ${path.module}/ansible/get-keycloak-info.yml \
        -e cluster_name='${var.CLUSTER_NAME}' \
        -e keycloak_hostname_var='${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}'
    EOT
  }
}
