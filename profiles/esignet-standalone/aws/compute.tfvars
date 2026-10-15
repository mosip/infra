# compute-specific values — eSignet standalone profile
# cluster_name/aws_provider_region/vpc_name come from ./common.tfvars

specific_availability_zones = []

k8s_instance_type   = "t3a.2xlarge"
nginx_instance_type = "t3a.2xlarge"

nginx_node_root_volume_size   = 24
k8s_instance_root_volume_size = 64

# Control-plane, ETCD, Worker — smaller cluster for standalone eSignet
k8s_control_plane_node_count = 1
k8s_etcd_node_count          = 1
k8s_worker_node_count        = 2

# nginx gets the certbot Route53 instance profile from the iam component.
# Set false when profile.yml uses another TLS mode (byo, http01, dns01 with
# a non-route53 provider).
attach_certbot_profile = true

# Power state (optional). Unset = Terraform starts instances when it creates
# them and leaves running/stopped alone afterwards (use the "instances
# start / stop" workflow). When set, every compute run enforces it.
# k8s_instance_state   = "stopped"                         # all cluster nodes
# k8s_node_state       = { "WORKER-NODE-5" = "stopped" }   # per node, overrides
# nginx_instance_state = "running"
