terraform {
  required_version = ">= 1.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Wait for NFS setup to complete
resource "null_resource" "wait_for_nfs" {
  provisioner "local-exec" {
    command = "sleep 30" # Wait for NFS to be ready
  }
}

# Install Rancher UI using Helm on the control plane
resource "null_resource" "install_rancher" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [null_resource.wait_for_nfs]

  connection {
    type        = "ssh"
    host        = var.CONTROL_PLANE_IPS[0] # Connect to first control plane node
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'Installing Rancher UI...'",
      
      # Wait for kubectl to be available
      "timeout 300 bash -c 'until kubectl get nodes; do sleep 5; done'",
      
      # Add Rancher Helm repository
      "helm repo add rancher-latest https://releases.rancher.com/server-charts/latest",
      "helm repo update",
      
      # Install cert-manager (required for Rancher)
      "kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml",
      "helm repo add jetstack https://charts.jetstack.io",
      "helm repo update",
      "helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.13.0",
      
      # Wait for cert-manager to be ready
      "kubectl wait --for=condition=ready pod -l app=cert-manager --timeout=300s -n cert-manager",
      "kubectl wait --for=condition=ready pod -l app=cainjector --timeout=300s -n cert-manager",
      "kubectl wait --for=condition=ready pod -l app=webhook --timeout=300s -n cert-manager",
      
      # Install Rancher
      "helm install rancher rancher-latest/rancher --namespace cattle-system --create-namespace --set hostname=${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"} --set bootstrapPassword=${var.RANCHER_BOOTSTRAP_PASSWORD} --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=admin@${var.CLUSTER_ENV_DOMAIN} --set letsEncrypt.ingress.class=nginx --set ingress.extraAnnotations.'kubernetes\\.io/ingress\\.class'=nginx --wait --timeout=600s",
      
      # Wait for Rancher to be ready
      "kubectl wait --for=condition=ready pod -l app=rancher --timeout=600s -n cattle-system",
      
      "echo 'Rancher UI installation completed successfully'"
    ]
  }

  triggers = {
    rancher_hostname = var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"
    cluster_name     = var.CLUSTER_NAME
  }
}

# Clone k8s-infra repository and install Keycloak
resource "null_resource" "install_keycloak" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [null_resource.install_rancher]

  connection {
    type        = "ssh"
    host        = var.CONTROL_PLANE_IPS[0] # Connect to first control plane node
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'Setting up Keycloak installation...'",
      
      # Clone k8s-infra repository if not already present
      "cd /home/ubuntu",
      "if [ ! -d 'k8s-infra' ]; then",
      "  git clone ${var.K8S_INFRA_REPO_URL}",
      "fi",
      "cd k8s-infra",
      "git fetch origin",
      "git checkout ${var.K8S_INFRA_BRANCH}",
      "git pull origin ${var.K8S_INFRA_BRANCH}",
      
      # Navigate to Keycloak installation directory
      "cd rancher/keycloak",
      
      # Make sure the install script is executable
      "chmod +x install.sh",
      
      # Run Keycloak installation
      "echo 'Installing Keycloak...'",
      "./install.sh ${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}",
      
      # Wait for Keycloak to be ready
      "kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak --timeout=600s -n keycloak || true",
      
      "echo 'Keycloak installation completed successfully'"
    ]
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

  connection {
    type        = "ssh"
    host        = var.CONTROL_PLANE_IPS[0]
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Rancher UI Status:'",
      "kubectl get pods -n cattle-system | grep rancher",
      "echo 'Rancher URL: https://${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"}'",
      "echo 'Bootstrap Password: ${var.RANCHER_BOOTSTRAP_PASSWORD}'"
    ]
  }
}

# Get Keycloak URL and status
resource "null_resource" "get_keycloak_info" {
  count      = var.ENABLE_RANCHER_KEYCLOAK ? 1 : 0
  depends_on = [null_resource.install_keycloak]

  connection {
    type        = "ssh"
    host        = var.CONTROL_PLANE_IPS[0]
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Keycloak Status:'",
      "kubectl get pods -n keycloak | grep keycloak || echo 'Keycloak pods not found'",
      "echo 'Keycloak URL: https://${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}'",
      "echo 'Access Keycloak admin console with credentials provided by the installation script'"
    ]
  }
}
