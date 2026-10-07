# compute-specific values — eSignet standalone profile
# cluster_name/aws_provider_region/vpc_name come from ../../../profiles/esignet-standalone/common.tfvars

specific_availability_zones = []

k8s_instance_type   = "t3a.2xlarge"
nginx_instance_type = "t3a.2xlarge"

nginx_node_root_volume_size   = 24
k8s_instance_root_volume_size = 64

# Control-plane, ETCD, Worker — smaller cluster for standalone eSignet
k8s_control_plane_node_count = 1
k8s_etcd_node_count          = 1
k8s_worker_node_count        = 2
