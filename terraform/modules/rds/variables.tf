variable "name" {
  type = string
}

variable "databases" {
  description = "Mapa servico => nome do banco"
  type        = map(string)
  default = {
    auth      = "auth_db"
    flags     = "flags_db"
    targeting = "targeting_db"
  }
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets privadas"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "SGs que podem acessar a porta 5432 (SG do cluster EKS)"
  type        = list(string)
}

variable "engine_version" {
  type    = string
  default = "17"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "master_username" {
  type    = string
  default = "togglemaster"
}

variable "tags" {
  type    = map(string)
  default = {}
}
