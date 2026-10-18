variable "name" {
  description = "Prefixo dos nomes dos recursos"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS (usado nas tags das subnets)"
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  description = "Quantidade de AZs (o EKS exige pelo menos 2)"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "Use entre 2 e 4 AZs."
  }
}

variable "enable_nat_gateway" {
  description = "Cria um NAT Gateway para as subnets privadas (necessario se os nodes ficarem nelas)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
