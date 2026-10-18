variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "role_arn" {
  description = "ARN da role usada pelo cluster e pelos nodes (LabRole no AWS Academy)"
  type        = string
}

variable "cluster_subnet_ids" {
  description = "Subnets onde o EKS coloca as ENIs do control plane"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets dos nodes (privadas, saindo pelo NAT)"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs que podem acessar o endpoint publico da API do Kubernetes"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  type    = list(string)
  default = []
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  type    = number
  default = 20
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "tags" {
  type    = map(string)
  default = {}
}
