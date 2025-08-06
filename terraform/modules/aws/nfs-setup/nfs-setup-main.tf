variable "NFS_SERVER_LOCATION" {
  description = "The NFS server location."
  type        = string
  validation {
    condition     = can(regex("^(/[^/ ]*)+/?$", var.NFS_SERVER_LOCATION))
    error_message = "The provided NFS_SERVER_LOCATION path must be a valid absolute path."
  }
}
variable "NFS_SERVER" {
  description = "The NFS server address, which can be a DNS name, an IPv4 address, or an IPv6 address."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.NFS_SERVER)) || can(regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", var.NFS_SERVER)) || can(regex("^(::|[a-fA-F0-9]{1,4}::?|::[a-fA-F0-9]{1,4})([a-fA-F0-9]{1,4}:){0,6}[a-fA-F0-9]{1,4}$", var.NFS_SERVER))
    error_message = "The NFS_SERVER must be a valid DNS name, an IPv4 address, or an IPv6 address."
  }
}
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
variable "CLUSTER_NAME" { type = string }

locals {
  NFS_CONFIG = {
    K8S_INFRA_REPO_URL               = var.K8S_INFRA_REPO_URL
    K8S_INFRA_BRANCH                 = var.K8S_INFRA_BRANCH
    NFS_SERVER                       = var.NFS_SERVER
    NFS_SERVER_LOCATION              = var.NFS_SERVER_LOCATION
    K8S_INFRA_NFS_LOCATION           = "./k8s-infra/storage-class/nfs"
    K8S_INFRA_NFS_SERVER_SCRIPT_NAME = "install-nfs-server.sh"
    K8S_INFRA_NFS_CSI_SCRIPT_NAME    = "install-nfs-csi.sh"

    NFS_SERVER_LOG_FILE_PATH = "/tmp/nfs-server-log"
    NFS_CSI_LOG_FILE_PATH    = "/tmp/nfs-csi-log"

    HELM_VERSION = "helm-v3.15.4-linux-amd64.tar.gz"
    CLUSTER_NAME = var.CLUSTER_NAME

  }
  NFS_ENV_VARS = [
    for key, value in local.NFS_CONFIG :
    "export ${key}=${value}"
    #"echo 'export ${key}=${value}' | sudo tee -a /etc/environment"
  ]
}
resource "null_resource" "nfs-server-setup" {
  connection {
    type        = "ssh"
    host        = var.NFS_SERVER
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
  }
  provisioner "remote-exec" {
    inline = concat(
      ["echo \"export NFS_SERVER_LOCATION=${var.NFS_SERVER_LOCATION}\" | sudo tee -a /etc/environment",
        "sudo source /etc/environment",
        "sudo bash ${local.NFS_CONFIG.K8S_INFRA_NFS_LOCATION}/${local.NFS_CONFIG.K8S_INFRA_NFS_SERVER_SCRIPT_NAME} | tee -a ${local.NFS_CONFIG.NFS_SERVER_LOG_FILE_PATH}-$( date +\"%d-%h-%Y-%H-%M\" ).log"
      ]
    )
  }
}

resource "null_resource" "nfs-csi-setup" {
  depends_on = [null_resource.nfs-server-setup]

  provisioner "local-exec" {
    command = join(" && ", concat(local.NFS_ENV_VARS, ["bash ${path.module}/nfs-csi.sh"]))
  }
}
