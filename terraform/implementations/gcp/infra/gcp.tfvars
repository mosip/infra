# GCP configuration
cluster_name = "mosip-gcp"
cluster_env_domain = "gcp.mosip.net"
mosip_email_id = "admin@example.com"
k8s_control_plane_node_count = 1
k8s_etcd_node_count = 1
k8s_worker_node_count = 1
subdomain_public = ["resident", "prereg", "esignet"]
subdomain_internal = ["admin", "iam", "activemq"]
rancher_import_url = "\"kubectl apply -f https://rancher.mosip.net/v3/import/placeholder.yaml\""
k8s_infra_repo_url = "https://github.com/mosip/k8s-infra.git"
k8s_infra_branch = "develop"

# GCP-specific configuration
gcp_project_id = "your-gcp-project-id"
gcp_provider_region = "us-central1"
k8s_instance_type = "e2-standard-4"
nginx_instance_type = "e2-standard-2"
gcp_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2004-lts"
ssh_key_name = "mosip-gcp"
gcp_dns_zone = "gcp.mosip.net"
vpc_name = "mosip-gcp-vpc"
nginx_node_root_volume_size = 50
nginx_node_additional_volume_size = 100
k8s_instance_root_volume_size = 50

# SSH Private Key (should be set via environment variable or terraform.tfvars)
# ssh_private_key = "your-private-key-content"
