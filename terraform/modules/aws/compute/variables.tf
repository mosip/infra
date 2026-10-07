variable "cluster_name" { type = string }

variable "ami" {
  type = string
  validation {
    condition     = can(regex("^ami-[a-f0-9]{17}$", var.ami))
    error_message = "Invalid AMI format. It should be in the format 'ami-xxxxxxxxxxxxxxxxx'"
  }
}

variable "ssh_key_name" { type = string }

variable "nginx_instance_type" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.nginx_instance_type))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}

variable "k8s_instance_type" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.k8s_instance_type))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}

variable "nginx_node_root_volume_size" { type = number }
variable "k8s_instance_root_volume_size" { type = number }

variable "public_subnet_ids" {
  description = "Public subnet IDs for the nginx instance"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for K8s instances"
  type        = list(string)
}

variable "nginx_sg_id" {
  description = "Security group ID for the nginx instance — looked up by tag from #274's security component"
  type        = string
}

variable "k8s_control_plane_sg_id" { type = string }
variable "k8s_etcd_sg_id" { type = string }
variable "k8s_worker_sg_id" { type = string }

variable "k8s_control_plane_node_count" { type = number }
variable "k8s_etcd_node_count" { type = number }
variable "k8s_worker_node_count" { type = number }

# NGINX TAG NAME
locals {
  nginx_tag_name = "${var.cluster_name}-NGINX-NODE"
}
