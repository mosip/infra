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

      # Export KUBECONFIG for ubuntu user and wait for kubectl to be available
      "export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml",
      "timeout 300 bash -c 'until kubectl get nodes; do sleep 5; done'",
      "echo 'Kubectl version:'",
      "kubectl version --client",

      # Check if helm is installed, if not install it
      "echo 'Checking Helm installation...'",
      "if ! command -v helm &> /dev/null; then",
      "  echo 'Helm not found, installing via curl...'",
      "  curl -fsSL https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz -o /tmp/helm.tar.gz",
      "  tar -xzf /tmp/helm.tar.gz -C /tmp",
      "  sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm",
      "  sudo chmod +x /usr/local/bin/helm",
      "  rm -rf /tmp/helm.tar.gz /tmp/linux-amd64",
      "  echo 'Helm installed successfully'",
      "fi",
      "echo 'Helm version:'",
      "helm version",

      # Install ingress-nginx only if not already installed
      "echo 'Checking ingress-nginx installation...'",
      "if ! helm list -n ingress-nginx | grep -q ingress-nginx; then",
      "  echo 'Installing ingress-nginx...'",
      "  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx",
      "  helm repo update",
      "  helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --version 4.10.0 --create-namespace --set controller.service.type=NodePort --set controller.service.nodePorts.http=30080 --set controller.service.nodePorts.https=30443 --set controller.config.use-forwarded-headers=true",
      "else",
      "  echo 'ingress-nginx already installed, skipping...'",
      "fi",

      # Add Rancher Helm repository
      "echo 'Adding Rancher Helm repository...'",
      "helm repo add rancher-latest https://releases.rancher.com/server-charts/latest || true",
      "helm repo update",

      # Install Rancher with updated configuration (only if not already installed)
      "echo 'Checking Rancher installation...'",
      "if ! helm list -n cattle-system | grep -q rancher; then",
      "  echo 'Installing Rancher...'",
      "  export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml",
      "  helm install rancher rancher-latest/rancher --namespace cattle-system --version=2.8.3 --create-namespace --set hostname=${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"} --set ingress.enabled=true --set ingress.includeDefaultExtraAnnotations=true --set ingress.extraAnnotations.'kubernetes\\.io/ingress\\.class'=nginx --set rancherImage=rancher/rancher --set replicas=1 --set tls=external --set-string bootstrapPassword=${var.RANCHER_BOOTSTRAP_PASSWORD}",
      "  # Wait for Rancher to be ready",
      "  kubectl wait --for=condition=ready pod -l app=rancher --timeout=600s -n cattle-system",
      "else",
      "  echo 'Rancher already installed, skipping...'",
      "fi",

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
      
      # Wait for Rancher to be fully ready
      "echo 'Verifying Rancher is fully operational...'",
      "export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml",
      "kubectl wait --for=condition=ready pod -l app=rancher --timeout=300s -n cattle-system",
      
      # Additional wait for Rancher to stabilize
      "echo 'Waiting 2 minutes for Rancher to stabilize...'",
      "sleep 120",
      "echo 'Wait complete, proceeding with Keycloak installation...'",

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

      # Verify kubeconfig file exists
      "echo 'Verifying kubeconfig file availability...'",
      "if [ ! -f /home/ubuntu/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml ]; then",
      "  echo 'ERROR: Kubeconfig file not found at /home/ubuntu/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml'",
      "  ls -la /home/ubuntu/.kube/ || echo 'Directory /home/ubuntu/.kube/ does not exist'",
      "  exit 1",
      "fi",
      "echo 'Kubeconfig file found successfully'",

      # Set the Keycloak hostname dynamically
      "KEYCLOAK_HOST='${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}'",
      
      # Create a wrapper script that sets KUBECONFIG and runs install.sh
      "echo 'Creating wrapper script for Keycloak installation...'",
      "cat > /tmp/install_keycloak_wrapper.sh << 'EOF'",
      "#!/bin/bash",
      "set -e",
      "export KUBECONFIG=/home/ubuntu/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml",
      "cd /home/ubuntu/k8s-infra/observation/keycloak",
      "./install.sh \"$1\"",
      "EOF",
      "chmod +x /tmp/install_keycloak_wrapper.sh",
      
      # Run the wrapper script
      "echo 'Installing Keycloak...'",
      "/tmp/install_keycloak_wrapper.sh \"$KEYCLOAK_HOST\"",

      # Wait for Keycloak to be ready
      "export KUBECONFIG=/home/ubuntu/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml",
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
      "export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml",
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
      "export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}-CONTROL-PLANE-NODE-1.yaml",
      "echo 'Keycloak Status:'",
      "kubectl get pods -n keycloak | grep keycloak || echo 'Keycloak pods not found'",
      "echo 'Keycloak URL: https://${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}'",
      "echo 'Access Keycloak admin console with credentials provided by the installation script'"
    ]
  }
}
