variable "cluster_name" { type = string }

variable "nginx_instance_id" {
  description = "Instance ID to attach volumes to — looked up by tag from #275's compute component"
  type        = string
}

variable "availability_zone" {
  description = "AZ the nginx instance actually landed in — volumes must be in the same AZ as the instance"
  type        = string
}

variable "nginx_tag_name" {
  description = "Base name used for volume tags, matches compute's nginx tag convention"
  type        = string
}

variable "nginx_node_ebs_volume_size" {
  description = "Size (GB) of the first EBS volume (/dev/sdb) — used for /srv/nfs, always created"
  type        = number
}

variable "nginx_node_ebs_volume_size_2" {
  description = "Size (GB) of the second EBS volume (/dev/sdc) — used for PostgreSQL, 0 disables"
  type        = number
  default     = 0
}

variable "nginx_node_ebs_volume_size_3" {
  description = "Size (GB) of the third EBS volume (/dev/sdd) — used for ActiveMQ, 0 disables"
  type        = number
  default     = 0
}

variable "enable_activemq_setup" {
  type    = bool
  default = false
}
