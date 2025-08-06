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
      "echo 'Setting up Rancher UI...'",
      
      # Wait for kubectl to be available and check version
      "timeout 300 bash -c 'until kubectl get nodes; do sleep 5; done'",
      "echo 'Kubectl version:'",
      "kubectl version --client",
      
      # Check if helm is installed, if not install it
      "echo 'Checking Helm installation...'",
      "if ! command -v helm &> /dev/null; then",
      "  echo 'Helm not found, installing...'",
      "  sudo apt update",
      "  sudo snap install helm --classic",
      "else",
      "  echo 'Helm version:'",
      "  helm version",
      "fi",
      
      # Install ingress-nginx
      "echo 'Installing ingress-nginx...'",
      "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx",
      "helm repo update",
      "helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --version 4.10.0 --create-namespace --set controller.service.type=NodePort --set controller.service.nodePorts.http=30080 --set controller.service.nodePorts.https=30443 --set controller.config.use-forwarded-headers=true",
      
      # Add Rancher Helm repository
      "echo 'Adding Rancher Helm repository...'",
      "helm repo add rancher-latest https://releases.rancher.com/server-charts/latest",
      "helm repo update",
      
      # Install Rancher with updated configuration
      "echo 'Installing Rancher...'",
      "helm install rancher rancher-stable/rancher --namespace cattle-system --version=2.8.3 --create-namespace --kube-version 1.28.9 --set hostname=${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"} --set ingress.enabled=true --set ingress.includeDefaultExtraAnnotations=true --set ingress.extraAnnotations.'kubernetes\\.io/ingress\\.class'=nginx --set rancherImage=rancher/rancher --set replicas=2 --set tls=external --set-string bootstrapPassword=${var.RANCHER_BOOTSTRAP_PASSWORD}",
      
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
      "cd observation/keycloak",
      
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
