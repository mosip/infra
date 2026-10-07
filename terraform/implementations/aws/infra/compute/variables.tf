# cluster_name, aws_provider_region, vpc_name come from ../profiles/<profile>/common.tfvars
# (shared across every component). Everything below is compute-specific and lives
# in this component's own profiles/<profile>/aws.tfvars.

variable "cluster_name" { type = string }
variable "aws_provider_region" { type = string }
variable "vpc_name" { type = string }

variable "specific_availability_zones" {
  description = "Specific AZs for VM deployment — [] uses all available AZs in the region (recommended, avoids InsufficientInstanceCapacity)"
  type        = list(string)
  default     = []
}

variable "ami" { type = string }
variable "ssh_key_name" { type = string }
variable "nginx_instance_type" { type = string }
variable "k8s_instance_type" { type = string }
variable "nginx_node_root_volume_size" { type = number }
variable "k8s_instance_root_volume_size" { type = number }

variable "k8s_control_plane_node_count" { type = number }
variable "k8s_etcd_node_count" { type = number }
variable "k8s_worker_node_count" { type = number }
