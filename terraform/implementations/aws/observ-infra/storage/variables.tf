# cluster_name/aws_provider_region come from ../common.tfvars

variable "cluster_name" { type = string }
variable "aws_provider_region" { type = string }

variable "nginx_node_ebs_volume_size" { type = number }
variable "nginx_node_ebs_volume_size_2" {
  type    = number
  default = 0
}
variable "nginx_node_ebs_volume_size_3" {
  type    = number
  default = 0
}
variable "enable_activemq_setup" {
  type    = bool
  default = false
}
