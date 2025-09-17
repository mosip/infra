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
      
      # Set KUBECONFIG environment variable for all kubectl commands
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",

      # Wait for kubectl to be available and check version
      "timeout 300 bash -c 'until sudo -E kubectl get nodes; do sleep 5; done'",
      "echo 'Kubectl version:'",
      "sudo -E kubectl version --client",

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

      # Create required namespaces
      "echo 'Creating required namespaces...'",
      "sudo -E kubectl create namespace cattle-system --dry-run=client -o yaml | sudo -E kubectl apply -f -",
      "sudo -E kubectl create namespace keycloak --dry-run=client -o yaml | sudo -E kubectl apply -f -",
      "sudo -E kubectl create namespace ingress-nginx --dry-run=client -o yaml | sudo -E kubectl apply -f -",

      # Install ingress-nginx
      "echo 'Installing ingress-nginx...'",
      "sudo -E helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx",
      "sudo -E helm repo update",
      "sudo -E helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --version 4.10.0 --set controller.service.type=NodePort --set controller.service.nodePorts.http=30080 --set controller.service.nodePorts.https=30443 --set controller.config.use-forwarded-headers=true",

      # Add Rancher Helm repository
      "echo 'Adding Rancher Helm repository...'",
      "sudo -E helm repo add rancher-latest https://releases.rancher.com/server-charts/latest",
      "sudo -E helm repo update",

      # Install Rancher with updated configuration (using fixed password for debugging)
      "echo 'Installing Rancher...'",
      "sudo -E helm upgrade --install rancher rancher-latest/rancher --namespace cattle-system --version=2.8.3 --set hostname=${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"} --set ingress.enabled=true --set ingress.includeDefaultExtraAnnotations=true --set ingress.extraAnnotations.'kubernetes\\.io/ingress\\.class'=nginx --set rancherImage=rancher/rancher --set replicas=2 --set tls=external --set-string bootstrapPassword=admin123",

      # Wait for Rancher to be ready
      "sudo -E kubectl wait --for=condition=ready pod -l app=rancher --timeout=600s -n cattle-system",

      "echo 'Rancher UI installation completed successfully'"
    ]
  }

  triggers = {
    rancher_hostname = var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"
    cluster_name     = var.CLUSTER_NAME
    always_run       = timestamp() # Force re-execution to ensure services are actually installed
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
      
      # Set KUBECONFIG environment variable for all kubectl commands
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",

      # Wait for kubectl to be available and check version
      "timeout 300 bash -c 'until sudo -E kubectl get nodes; do sleep 5; done'",
      "echo 'Kubectl version:'",
      "sudo -E kubectl version --client",

      # Create keycloak namespace if it doesn't exist
      "echo 'Creating Keycloak namespace...'",
      "sudo -E kubectl create namespace keycloak --dry-run=client -o yaml | sudo -E kubectl apply -f -",

      # Add Bitnami Helm repository for Keycloak
      "echo 'Adding Bitnami Helm repository...'",
      "sudo -E helm repo add bitnami https://charts.bitnami.com/bitnami",
      "sudo -E helm repo update",

      # Install Keycloak using Helm
      "echo 'Installing Keycloak...'",
      "sudo -E helm upgrade --install keycloak bitnami/keycloak --namespace keycloak --version 17.3.6 --set auth.adminUser=admin --set auth.adminPassword=admin123 --set service.type=ClusterIP --set ingress.enabled=true --set ingress.ingressClassName=nginx --set ingress.hostname=${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"} --set ingress.tls=true --set ingress.annotations.'cert-manager\\.io/cluster-issuer'=letsencrypt-prod --set ingress.annotations.'nginx\\.ingress\\.kubernetes\\.io/proxy-buffer-size'=128k --set postgresql.auth.postgresPassword=postgres123 --set postgresql.auth.database=keycloak",

      # Wait for Keycloak to be ready
      "sudo -E kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak --timeout=600s -n keycloak",

      "echo 'Keycloak installation completed successfully'"
    ]
  }

  triggers = {
    keycloak_hostname = var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"
    cluster_name      = var.CLUSTER_NAME
    always_run        = timestamp() # Force re-execution to ensure services are actually installed
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
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "echo 'Rancher UI Status:'",
      "sudo -E kubectl get pods -n cattle-system | grep rancher",
      "echo 'Rancher URL: https://${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"}'",
      "echo 'Bootstrap Password: admin123'"
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
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "echo 'Keycloak Status:'",
      "sudo -E kubectl get pods -n keycloak | grep keycloak || echo 'Keycloak pods not found'",
      "echo 'Keycloak URL: https://${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}'",
      "echo 'Access Keycloak admin console with credentials provided by the installation script'"
    ]
  }
}
