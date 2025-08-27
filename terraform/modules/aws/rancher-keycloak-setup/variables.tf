variable "SSH_PRIVATE_KEY" {
  description = "SSH private key for remote execution"
  type        = string
}

variable "K8S_INFRA_REPO_URL" {
  description = "URL of the k8s-infra repository"
  type        = string
}

variable "K8S_INFRA_BRANCH" {
  description = "Branch of the k8s-infra repository"
  type        = string
}

variable "CLUSTER_NAME" {
  description = "Name of the cluster"
  type        = string
}

variable "CLUSTER_ENV_DOMAIN" {
  description = "Cluster environment domain"
  type        = string
}

variable "RANCHER_HOSTNAME" {
  description = "Hostname for Rancher UI"
  type        = string
  default     = ""
}

variable "KEYCLOAK_HOSTNAME" {
  description = "Hostname for Keycloak"
  type        = string
  default     = ""
}

variable "RANCHER_BOOTSTRAP_PASSWORD" {
  description = "Bootstrap password for Rancher"
  type        = string
  default     = "admin"
}

variable "ENABLE_RANCHER_KEYCLOAK" {
  description = "Enable Rancher and Keycloak installation"
  type        = bool
  default     = true
}

variable "CONTROL_PLANE_IPS" {
  description = "List of control plane node IPs"
  type        = list(string)
}

variable "NGINX_PUBLIC_IP" {
  description = "Public IP of NGINX server"
  type        = string
}
