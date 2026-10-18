variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets privadas"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "SGs que podem acessar a porta 6379 (SG do cluster EKS)"
  type        = list(string)
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "tags" {
  type    = map(string)
  default = {}
}
