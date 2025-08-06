output "rancher_url" {
  description = "URL for accessing Rancher UI"
  value       = var.ENABLE_RANCHER_KEYCLOAK ? "https://${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"}" : "Rancher installation disabled"
}

output "keycloak_url" {
  description = "URL for accessing Keycloak"
  value       = var.ENABLE_RANCHER_KEYCLOAK ? "https://${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}" : "Keycloak installation disabled"
}

output "rancher_bootstrap_password" {
  description = "Bootstrap password for Rancher UI"
  value       = var.ENABLE_RANCHER_KEYCLOAK ? var.RANCHER_BOOTSTRAP_PASSWORD : "N/A"
  sensitive   = true
}

output "installation_status" {
  description = "Status of Rancher and Keycloak installation"
  value       = var.ENABLE_RANCHER_KEYCLOAK ? "Rancher and Keycloak installation completed" : "Rancher and Keycloak installation disabled"
}

output "rancher_namespace" {
  description = "Kubernetes namespace where Rancher is deployed"
  value       = var.ENABLE_RANCHER_KEYCLOAK ? "cattle-system" : "N/A"
}

output "keycloak_namespace" {
  description = "Kubernetes namespace where Keycloak is deployed"
  value       = var.ENABLE_RANCHER_KEYCLOAK ? "keycloak" : "N/A"
}

output "next_steps" {
  description = "Next steps after installation"
  value = var.ENABLE_RANCHER_KEYCLOAK ? [
    "1. Access Rancher UI at: https://${var.RANCHER_HOSTNAME != "" ? var.RANCHER_HOSTNAME : "rancher.${var.CLUSTER_ENV_DOMAIN}"}",
    "2. Login with bootstrap password: ${var.RANCHER_BOOTSTRAP_PASSWORD}",
    "3. Access Keycloak at: https://${var.KEYCLOAK_HOSTNAME != "" ? var.KEYCLOAK_HOSTNAME : "iam.${var.CLUSTER_ENV_DOMAIN}"}",
    "4. Configure Keycloak admin credentials as provided by the installation script",
    "5. Set up MOSIP integration using Rancher and Keycloak"
  ] : [
    "Rancher and Keycloak installation was disabled. Set ENABLE_RANCHER_KEYCLOAK=true to enable."
  ]
}
