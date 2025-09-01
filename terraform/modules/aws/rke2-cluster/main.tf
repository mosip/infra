variable "K8S_CLUSTER_PRIVATE_IPS" { type = map(string) }
variable "SSH_PRIVATE_KEY" { type = string }
variable "K8S_INFRA_REPO_URL" {
  description = "The URL of the Kubernetes infrastructure GitHub repository"
  type        = string
  validation {
    condition     = can(regex("^https://github\\.com/.+/.+\\.git$", var.K8S_INFRA_REPO_URL))
    error_message = "The K8S_INFRA_REPO_URL must be a valid GitHub repository URL ending with .git"
  }
}

variable "K8S_INFRA_BRANCH" { type = string }
variable "RANCHER_IMPORT_URL" {
  description = "Rancher import URL for kubectl apply"
  type        = string
  validation {
    condition     = can(regex("^\"kubectl apply -f https://rancher\\.mosip\\.net/v3/import/[a-zA-Z0-9_\\-]+\\.yaml\"$", var.RANCHER_IMPORT_URL))
    error_message = "The RANCHER_IMPORT_URL must be in the format: '\"kubectl apply -f https://rancher.mosip.net/v3/import/<ID>.yaml\"'"
  }
}

variable "enable_rancher_import" {
  description = "Set to true to enable Rancher import"
  type        = bool
  default     = false
}

# Generate a random string (token)
resource "random_string" "K8S_TOKEN" {
  length  = 32
  upper   = true
  lower   = true
  numeric = true
  special = false
}

locals {
  CONTROL_PLANE_NODE_1        = element([for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value if length(regexall(".*CONTROL-PLANE-NODE-1", key)) > 0], 0)
  K8S_CLUSTER_PRIVATE_IPS_STR = join(",", [for key, value in var.K8S_CLUSTER_PRIVATE_IPS : "${key}=${value}"])

  # Base RKE configuration
  RKE_CONFIG_BASE = {
    ENV_VAR_FILE                = "/etc/environment"
    CONTROL_PLANE_NODE_1        = local.CONTROL_PLANE_NODE_1
    WORK_DIR                    = "/home/ubuntu/"
    RKE2_CONFIG_DIR             = "/etc/rancher/rke2"
    INSTALL_RKE2_VERSION        = "v1.28.9+rke2r1"
    K8S_INFRA_REPO_URL          = var.K8S_INFRA_REPO_URL
    K8S_INFRA_BRANCH            = var.K8S_INFRA_BRANCH
    RKE2_LOCATION               = "/home/ubuntu/k8s-infra/k8-cluster/on-prem/rke2/"
    K8S_CLUSTER_PRIVATE_IPS_STR = local.K8S_CLUSTER_PRIVATE_IPS_STR
    K8S_TOKEN                   = random_string.K8S_TOKEN.result
  }

  # Conditional RKE configuration with Rancher import URL only when enabled
  RKE_CONFIG = var.enable_rancher_import ? merge(local.RKE_CONFIG_BASE, {
    RANCHER_IMPORT_URL = var.RANCHER_IMPORT_URL
  }) : local.RKE_CONFIG_BASE

  datetime = formatdate("2006-01-02_15-04-05", timestamp())
  backup_command = [
    "sudo cp ${local.RKE_CONFIG.ENV_VAR_FILE} /tmp/environment-bkp-${local.datetime} || true"
  ]

  update_commands = [
    for key, value in local.RKE_CONFIG :
    "sudo sed -i \"/^${key}=/d\" ${local.RKE_CONFIG.ENV_VAR_FILE} && echo '${key}=${value}' | sudo tee -a ${local.RKE_CONFIG.ENV_VAR_FILE}"
  ]

  k8s_env_vars = concat(local.backup_command, local.update_commands)
}

# Wait for SSH to be available
resource "null_resource" "wait_for_ssh" {
  for_each = var.K8S_CLUSTER_PRIVATE_IPS

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for SSH to be available on ${each.value}..."
      max_attempts=30
      attempt=1
      
      while [ $attempt -le $max_attempts ]; do
        echo "SSH check attempt $attempt/$max_attempts for ${each.key}"
        
        # Check if SSH port is open
        if nc -z -w5 ${each.value} 22 2>/dev/null; then
          echo "SSH port 22 is open on ${each.value}"
          
          # Test actual SSH connection
          echo "${var.SSH_PRIVATE_KEY}" > /tmp/${each.key}-sshkey-test
          chmod 400 /tmp/${each.key}-sshkey-test
          
          if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
                 -i /tmp/${each.key}-sshkey-test ubuntu@${each.value} \
                 'echo "SSH connection successful"' 2>/dev/null; then
            echo "SSH connection successful to ${each.value}"
            rm -f /tmp/${each.key}-sshkey-test
            break
          else
            echo "SSH connection failed, retrying..."
            rm -f /tmp/${each.key}-sshkey-test
          fi
        else
          echo "SSH port not yet open on ${each.value}"
        fi
        
        sleep 10
        attempt=$((attempt + 1))
      done
      
      if [ $attempt -gt $max_attempts ]; then
        echo "Failed to establish SSH connection to ${each.value} after $max_attempts attempts"
        exit 1
      fi
    EOF
  }
}

# Primary cluster setup with improved error handling
resource "null_resource" "rke2-primary-cluster-setup" {
  depends_on = [null_resource.wait_for_ssh]
  
  triggers = {
    config_hash = md5(jsonencode(local.RKE_CONFIG))
    script_hash = filemd5("${path.module}/rke2-setup.sh")
  }

  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "15m"
    agent       = false
    
    # SSH connection options for stability
    host_key = null
  }

  # Wait for system to be ready and update packages
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for system to be ready...'",
      "sudo cloud-init status --wait || echo 'Cloud-init wait completed with warnings'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for boot to finish...'; sleep 5; done",
      "echo 'System is ready, updating packages...'",
      "sudo apt-get update -y",
      "echo 'Package update completed'"
    ]
    
    on_failure = continue
  }

  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"
  }

  # Set environment variables with error handling
  provisioner "remote-exec" {
    inline = concat(
      [
        "set -e",  # Exit on error
        "echo 'Setting up environment variables...'",
      ],
      local.k8s_env_vars,
      [
        "echo 'Environment variables set successfully'",
        "chmod +x /tmp/rke2-setup.sh"
      ]
    )
    
    on_failure = fail
  }

  # Execute setup script with timeout and better process management
  provisioner "remote-exec" {
    inline = [
      "echo 'Starting RKE2 setup script with timeout...'",
      "nohup sudo timeout 900 bash /tmp/rke2-setup.sh > /tmp/rke2-setup.log 2>&1 &",
      "SETUP_PID=$!",
      "echo \"Setup process started with PID: $SETUP_PID\"",
      "",
      "# Monitor the process",
      "while kill -0 $SETUP_PID 2>/dev/null; do",
      "  echo 'RKE2 setup still running...'",
      "  sleep 30",
      "done",
      "",
      "# Wait for the process to complete",
      "wait $SETUP_PID",
      "EXIT_CODE=$?",
      "",
      "# Show the log output",
      "echo 'Setup completed. Log output:'",
      "tail -50 /tmp/rke2-setup.log",
      "",
      "if [ $EXIT_CODE -eq 0 ]; then",
      "  echo 'RKE2 setup completed successfully'",
      "else",
      "  echo \"RKE2 setup failed with exit code: $EXIT_CODE\"",
      "  echo 'Full log:'",
      "  cat /tmp/rke2-setup.log",
      "  exit $EXIT_CODE",
      "fi"
    ]
    
    on_failure = fail
  }
}

# Cluster setup for remaining nodes
resource "null_resource" "rke2-cluster-setup" {
  depends_on = [null_resource.rke2-primary-cluster-setup]
  for_each   = var.K8S_CLUSTER_PRIVATE_IPS
  
  triggers = {
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
    config_hash = md5(jsonencode(local.RKE_CONFIG))
  }

  connection {
    type        = "ssh"
    host        = each.value
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "15m"
    agent       = false
    host_key    = null
  }

  # Wait for system readiness and update packages
  provisioner "remote-exec" {
    inline = [
      "echo 'Checking system readiness...'",
      "sudo cloud-init status --wait || echo 'Cloud-init completed with warnings'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for boot...'; sleep 5; done",
      "echo 'System ready, updating packages...'",
      "sudo apt-get update -y",
      "echo 'Package update completed for ${each.key}'"
    ]
    
    on_failure = continue
  }

  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"
  }

  # Set environment variables
  provisioner "remote-exec" {
    inline = concat(
      ["set -e", "echo 'Setting environment variables for ${each.key}...'"],
      local.k8s_env_vars,
      ["chmod +x /tmp/rke2-setup.sh"]
    )
  }

  # Execute setup with timeout and better monitoring
  provisioner "remote-exec" {
    inline = [
      "echo 'Starting RKE2 setup for ${each.key} with timeout...'",
      "",
      "# Wait for control plane if this is not the control plane node",
      "if [ '${each.value}' != '${local.CONTROL_PLANE_NODE_1}' ]; then",
      "    echo 'Waiting for control plane to be ready...'",
      "    max_wait=300",
      "    wait_time=0",
      "    while [ $wait_time -lt $max_wait ]; do",
      "        if nc -z ${local.CONTROL_PLANE_NODE_1} 6443; then",
      "            echo 'Control plane is ready'",
      "            break",
      "        fi",
      "        echo \"Waiting for control plane... ($wait_time/$max_wait seconds)\"",
      "        sleep 10",
      "        wait_time=$((wait_time + 10))",
      "    done",
      "fi",
      "",
      "# Run setup with timeout and logging",
      "nohup sudo timeout 900 bash /tmp/rke2-setup.sh > /tmp/rke2-setup.log 2>&1 &",
      "SETUP_PID=$!",
      "echo \"Setup process started with PID: $SETUP_PID\"",
      "",
      "# Monitor the process",
      "while kill -0 $SETUP_PID 2>/dev/null; do",
      "  echo 'RKE2 setup still running for ${each.key}...'",
      "  sleep 30",
      "done",
      "",
      "# Wait for completion and get exit code",
      "wait $SETUP_PID",
      "EXIT_CODE=$?",
      "",
      "# Show log output",
      "echo 'Setup completed for ${each.key}. Recent log output:'",
      "tail -50 /tmp/rke2-setup.log",
      "",
      "if [ $EXIT_CODE -eq 0 ]; then",
      "  echo 'RKE2 setup completed successfully for ${each.key}'",
      "else",
      "  echo \"RKE2 setup failed for ${each.key} with exit code: $EXIT_CODE\"",
      "  echo 'Full log:'",
      "  cat /tmp/rke2-setup.log",
      "  exit $EXIT_CODE",
      "fi"
    ]
  }
}

# Rancher import with improved error handling
resource "null_resource" "rancher-import" {
  count      = var.enable_rancher_import ? 1 : 0
  depends_on = [null_resource.rke2-cluster-setup]
  
  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "20m"
    agent       = false
    host_key    = null
  }

  # Wait for RKE2 to be fully ready
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for RKE2 to be ready...'",
      "sudo systemctl is-active --quiet rke2-server || (echo 'RKE2 server not active' && exit 1)",
      "while [ ! -f /etc/rancher/rke2/rke2.yaml ]; do echo 'Waiting for kubeconfig...'; sleep 10; done",
      "echo 'RKE2 is ready'"
    ]
  }

  # Setup kubectl and import to Rancher
  provisioner "remote-exec" {
    inline = [
      <<-EOF
        set -e
        echo "Setting up kubectl and importing to Rancher..."
        
        # Setup kubectl with retry
        MAX_ATTEMPTS=3
        ATTEMPT=1
        
        while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            echo "Kubectl setup attempt $ATTEMPT/$MAX_ATTEMPTS"
            
            if mkdir -p ~/.kube/ && \
               sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config && \
               sudo chown -R $USER:$USER ~/.kube && \
               sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl && \
               sudo chmod 400 ~/.kube/config && \
               sudo chmod +x /bin/kubectl; then
                echo "Kubectl setup successful"
                break
            else
                echo "Kubectl setup failed on attempt $ATTEMPT"
                if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
                    exit 1
                fi
                sleep 10
                ATTEMPT=$((ATTEMPT + 1))
            fi
        done
        
        # Test kubectl connectivity
        echo "Testing kubectl connectivity..."
        kubectl get nodes || (echo "kubectl connectivity test failed" && exit 1)
        
        # Import to Rancher with retry
        echo "Importing cluster to Rancher..."
        ATTEMPT=1
        
        while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            echo "Rancher import attempt $ATTEMPT/$MAX_ATTEMPTS"
            
            if eval ${var.RANCHER_IMPORT_URL}; then
                echo "Rancher import command executed successfully"
                
                # Wait for cattle-system namespace
                echo "Waiting for cattle-system namespace..."
                timeout 300 bash -c 'while ! kubectl get namespace cattle-system 2>/dev/null; do sleep 5; done' || true
                
                # Patch deployment if it exists
                if kubectl get deployment cattle-cluster-agent -n cattle-system 2>/dev/null; then
                    echo "Patching cattle-cluster-agent deployment..."
                    kubectl -n cattle-system patch deployment cattle-cluster-agent -p '{"spec": {"template": {"spec": {"dnsPolicy": "Default"}}}}' || true
                fi
                
                # Wait for deployment to be ready
                echo "Waiting for cattle-system deployments..."
                sleep 420
                kubectl -n cattle-system rollout status deploy --timeout=300s || echo "Rollout status check completed with warnings"
                sleep 30
                
                echo "Rancher import completed successfully"
                break
            else
                echo "Rancher import failed on attempt $ATTEMPT"
                if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
                    echo "Rancher import failed after all attempts, but continuing..."
                    break
                fi
                sleep 30
                ATTEMPT=$((ATTEMPT + 1))
            fi
        done
      EOF
    ]
    
    on_failure = continue  # Don't fail the entire deployment if Rancher import fails
  }
}

# Download kubeconfig files with improved error handling
resource "null_resource" "download-k8s-kubeconfig" {
  depends_on = [null_resource.rke2-cluster-setup]
  for_each   = var.K8S_CLUSTER_PRIVATE_IPS
  
  triggers = {
    node_hash = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
  }

  provisioner "local-exec" {
    command = <<-EOF
      set -e
      echo "Downloading kubeconfig for ${each.key}..."
      
      # Create temporary SSH key file
      echo "${var.SSH_PRIVATE_KEY}" > /tmp/${each.key}-sshkey
      chmod 400 /tmp/${each.key}-sshkey
      
      # Download with retry logic
      MAX_ATTEMPTS=5
      ATTEMPT=1
      
      while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
          echo "Download attempt $ATTEMPT/$MAX_ATTEMPTS for ${each.key}"
          
          if scp -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes \
                 -i /tmp/${each.key}-sshkey \
                 ubuntu@${each.value}:/home/ubuntu/.kube/${each.key}.yaml \
                 ${each.key}.yaml 2>/dev/null; then
              echo "Successfully downloaded kubeconfig for ${each.key}"
              break
          else
              echo "Download failed for ${each.key} on attempt $ATTEMPT"
              if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
                  echo "Failed to download kubeconfig for ${each.key} after all attempts"
                  # Don't exit with error, just log the failure
                  echo "Continuing without kubeconfig for ${each.key}"
              else
                  sleep 15
                  ATTEMPT=$((ATTEMPT + 1))
              fi
          fi
      done
      
      # Clean up temporary SSH key
      rm -f /tmp/${each.key}-sshkey
    EOF
    
    on_failure = continue
  }
}

# Download kubectl binary with retry
resource "null_resource" "download-kubectl-file" {
  depends_on = [null_resource.rke2-cluster-setup]
  
  provisioner "local-exec" {
    command = <<-EOF
      set -e
      echo "Downloading kubectl binary..."
      
      # Create temporary SSH key file
      echo "${var.SSH_PRIVATE_KEY}" > /tmp/control-plane-sshkey
      chmod 400 /tmp/control-plane-sshkey
      
      # Download with retry logic
      MAX_ATTEMPTS=5
      ATTEMPT=1
      
      while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
          echo "Kubectl download attempt $ATTEMPT/$MAX_ATTEMPTS"
          
          if scp -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes \
                 -i /tmp/control-plane-sshkey \
                 ubuntu@${local.CONTROL_PLANE_NODE_1}:/var/lib/rancher/rke2/bin/kubectl \
                 kubectl 2>/dev/null; then
              echo "Successfully downloaded kubectl binary"
              chmod +x kubectl
              break
          else
              echo "Kubectl download failed on attempt $ATTEMPT"
              if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
                  echo "Failed to download kubectl after all attempts"
                  echo "You may need to manually download kubectl from the control plane"
              else
                  sleep 15
                  ATTEMPT=$((ATTEMPT + 1))
              fi
          fi
      done
      
      # Clean up temporary SSH key
      rm -f /tmp/control-plane-sshkey
    EOF
    
    on_failure = continue
  }
}

# Health check resource to verify cluster status
resource "null_resource" "cluster_health_check" {
  depends_on = [null_resource.rke2-cluster-setup]
  
  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "10m"
    agent       = false
    host_key    = null
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
        echo "Performing cluster health check..."
        
        # Wait for kubectl to be available
        while [ ! -f /var/lib/rancher/rke2/bin/kubectl ]; do
            echo "Waiting for kubectl binary..."
            sleep 10
        done
        
        # Setup kubectl if not already done
        if [ ! -f ~/.kube/config ]; then
            mkdir -p ~/.kube/
            sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
            sudo chown -R $USER:$USER ~/.kube
            sudo chmod 400 ~/.kube/config
        fi
        
        # Add kubectl to PATH for this session
        export PATH=$PATH:/var/lib/rancher/rke2/bin
        
        # Wait for cluster to be ready
        echo "Waiting for cluster to be ready..."
        max_wait=300
        wait_time=0
        
        while [ $wait_time -lt $max_wait ]; do
            if /var/lib/rancher/rke2/bin/kubectl get nodes >/dev/null 2>&1; then
                echo "Cluster is responding to kubectl commands"
                /var/lib/rancher/rke2/bin/kubectl get nodes
                break
            fi
            echo "Waiting for cluster... ($wait_time/$max_wait seconds)"
            sleep 10
            wait_time=$((wait_time + 10))
        done
        
        echo "Cluster health check completed"
      EOF
    ]
    
    on_failure = continue
  }
}

output "CONTROL_PLANE_NODE_1" {
  value = local.CONTROL_PLANE_NODE_1
}

output "K8S_CLUSTER_PRIVATE_IPS_STR" {
  value = local.K8S_CLUSTER_PRIVATE_IPS_STR
}

output "K8S_TOKEN" {
  value     = random_string.K8S_TOKEN.result
  sensitive = true
}
