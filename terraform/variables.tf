variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  description = "Prefixo usado nos nomes dos recursos"
  type        = string
  default     = "togglemaster"
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "lab_role_name" {
  description = "Role pre-existente do AWS Academy usada pelo EKS e pelos nodes"
  type        = string
  default     = "LabRole"
}

# ---------- Rede ----------

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "nodes_in_private_subnets" {
  description = "true: nodes em subnets privadas + NAT Gateway (mais seguro, ~US$ 0,045/h). false: nodes em subnets publicas, sem NAT (mais barato)."
  type        = bool
  default     = true
}

# ---------- EKS ----------

variable "cluster_name" {
  type    = string
  default = "togglemaster"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
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

# ---------- Dados ----------

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}
