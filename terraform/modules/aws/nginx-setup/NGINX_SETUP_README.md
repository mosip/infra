# NGINX Setup Module - Flexible Configuration

This module supports both **MOSIP** and **Observability** NGINX configurations.

## Overview

The `nginx-setup` module can now handle two different types of NGINX configurations:

1. **MOSIP** - For MOSIP application traffic
2. **Observability** - For Rancher UI and monitoring services

## Key Differences

### MOSIP Configuration
- **Location**: `./k8s-infra/nginx/mosip/`
- **Variables Prefix**: `cluster_*`
- **Domains**: Multiple MOSIP public domains
- **Node Ports**: 
  - Public: 30080
  - Internal: 31080
  - PostgreSQL: 31432
  - MinIO: 30900
  - ActiveMQ: 31616

### Observability Configuration
- **Location**: `./k8s-infra/nginx/observation/`
- **Variables Prefix**: `observation_*`
- **Domains**: Rancher and IAM
  - `rancher.<domain>`
  - `iam.<domain>`
- **Node Port**: 30080 (single ingress)

## Usage

### For MOSIP Infrastructure

```hcl
module "nginx_setup" {
  source = "../../modules/aws/nginx-setup"

  NGINX_PUBLIC_IP                       = var.nginx_public_ip
  NGINX_PRIVATE_IP                      = var.nginx_private_ip
  CLUSTER_ENV_DOMAIN                    = var.cluster_env_domain
  MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST = var.cluster_nodes_ips
  MOSIP_PUBLIC_DOMAIN_LIST              = var.public_domains
  CERTBOT_EMAIL                         = var.certbot_email
  SSH_PRIVATE_KEY                       = var.ssh_private_key
  K8S_INFRA_REPO_URL                    = var.k8s_infra_repo_url
  K8S_INFRA_BRANCH                      = var.k8s_infra_branch
  NGINX_TYPE                            = "mosip"  # Default
}
```

### For Observability Infrastructure

```hcl
module "nginx_observability_setup" {
  source = "../../modules/aws/nginx-setup"

  NGINX_PUBLIC_IP                       = var.nginx_public_ip
  NGINX_PRIVATE_IP                      = var.nginx_private_ip
  CLUSTER_ENV_DOMAIN                    = var.cluster_env_domain
  MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST = join(",", [node1, node2, node3])
  MOSIP_PUBLIC_DOMAIN_LIST              = join(",", [
    "rancher.${var.cluster_env_domain}",
    "iam.${var.cluster_env_domain}"
  ])
  CERTBOT_EMAIL                         = var.certbot_email
  SSH_PRIVATE_KEY                       = var.ssh_private_key
  K8S_INFRA_REPO_URL                    = var.k8s_infra_repo_url
  K8S_INFRA_BRANCH                      = var.k8s_infra_branch
  NGINX_TYPE                            = "observability"  # Set to observability
}
```

## Variables

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `NGINX_PUBLIC_IP` | Public IP of NGINX server | string |
| `NGINX_PRIVATE_IP` | Private IP of NGINX server | string |
| `CLUSTER_ENV_DOMAIN` | Base domain for the cluster | string |
| `MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST` | Comma-separated list of cluster node IPs | string |
| `MOSIP_PUBLIC_DOMAIN_LIST` | Comma-separated list of public domains | string |
| `CERTBOT_EMAIL` | Email for Let's Encrypt certificates | string |
| `SSH_PRIVATE_KEY` | SSH private key for connection | string |
| `K8S_INFRA_REPO_URL` | GitHub repo URL for k8s-infra | string |

### Optional Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `K8S_INFRA_BRANCH` | Branch of k8s-infra repo | string | `main` |
| `NGINX_TYPE` | Type: `mosip` or `observability` | string | `mosip` |

## Environment Variables Exported

### MOSIP Type
```bash
cluster_env_domain
cluster_nginx_certs
cluster_nginx_cert_key
cluster_node_ips
cluster_public_domains
cluster_ingress_public_nodeport
cluster_ingress_internal_nodeport
cluster_ingress_postgres_nodeport
cluster_ingress_minio_nodeport
cluster_ingress_activemq_nodeport
cluster_nginx_internal_ip
cluster_nginx_public_ip
certbot_email
```

### Observability Type
```bash
observation_nginx_certs
observation_nginx_cert_key
observation_cluster_node_ips
observation_ingress_nodeport
observation_nginx_ip
```

## Script Behavior

The `nginx-setup.sh` script:
1. Detects which type based on environment variables
2. Installs NGINX and SSL dependencies
3. Generates SSL certificates (for MOSIP type)
4. Clones k8s-infra repository
5. Navigates to appropriate nginx location
6. Runs the type-specific `install.sh` script

## Prerequisites

1. WireGuard VPN connection established (for private IP access)
2. Route53 DNS configuration (for Let's Encrypt DNS challenge)
3. Appropriate k8s-infra repository with:
   - `nginx/mosip/install.sh` for MOSIP
   - `nginx/observation/install.sh` for Observability

## Notes

- Both types can coexist on different NGINX VMs
- MOSIP NGINX handles application traffic
- Observability NGINX handles Rancher UI and monitoring access
- SSL certificates are auto-generated for MOSIP type
- Observability type assumes certificates are configured separately or uses existing setup
