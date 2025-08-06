# Azure configuration
cluster_name = "mosip-azure"
cluster_env_domain = "azure.mosip.net"
mosip_email_id = "admin@example.com"
k8s_control_plane_node_count = 1
k8s_etcd_node_count = 1
k8s_worker_node_count = 1
subdomain_public = ["resident", "prereg", "esignet"]
subdomain_internal = ["admin", "iam", "activemq"]
rancher_import_url = "\"kubectl apply -f https://rancher.mosip.net/v3/import/placeholder.yaml\""
k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
k8s_infra_branch = "develop"

# Azure-specific configuration
azure_provider_region = "East US"
k8s_instance_type = "Standard_D4s_v3"
nginx_instance_type = "Standard_D2s_v3"
azure_image = "/subscriptions/your-subscription-id/resourceGroups/your-rg/providers/Microsoft.Compute/images/ubuntu-20-04"
ssh_key_name = "mosip-azure"
azure_dns_zone = "azure.mosip.net"
vpc_name = "mosip-azure-vnet"
nginx_node_root_volume_size = 50
nginx_node_additional_volume_size = 100
k8s_instance_root_volume_size = 50

# SSH Private Key (should be set via environment variable or terraform.tfvars)
# ssh_private_key = "your-private-key-content"
