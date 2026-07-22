# compute-specific values — observ-infra (single-node observability cluster)
# cluster_name/aws_provider_region/vpc_name come from ../common.tfvars

specific_availability_zones = []

# Minimal node counts for observability — single control-plane node, no
# etcd/worker groups.
k8s_control_plane_node_count = 1
k8s_etcd_node_count          = 0
k8s_worker_node_count        = 0

# Minimal instance types for observability
k8s_instance_type   = "t3a.2xlarge"
nginx_instance_type = "t3a.large"

nginx_node_root_volume_size   = 24
k8s_instance_root_volume_size = 32
