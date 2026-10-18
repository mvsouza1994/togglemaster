# ToggleMaster - infraestrutura completa (Fase 3).
# Cada bloco abaixo e um modulo independente em ./modules.

locals {
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# AWS Academy: nao podemos criar IAM. Lemos a LabRole que ja existe na conta
# e usamos no cluster e nos nodes. Nenhum aws_iam_role/aws_iam_policy neste projeto.
data "aws_iam_role" "lab" {
  name = var.lab_role_name
}

module "network" {
  source = "./modules/network"

  name               = var.project
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  enable_nat_gateway = var.nodes_in_private_subnets
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  role_arn           = data.aws_iam_role.lab.arn

  cluster_subnet_ids = concat(module.network.private_subnet_ids, module.network.public_subnet_ids)
  node_subnet_ids    = var.nodes_in_private_subnets ? module.network.private_subnet_ids : module.network.public_subnet_ids

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
}

module "rds" {
  source = "./modules/rds"

  name                       = var.project
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  instance_class             = var.db_instance_class
}

module "elasticache" {
  source = "./modules/elasticache"

  name                       = var.project
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  node_type                  = var.redis_node_type
}

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = "ToggleMasterAnalytics"
}

module "sqs" {
  source = "./modules/sqs"

  queue_name = "${var.project}-events"
}

module "ecr" {
  source = "./modules/ecr"

  prefix = var.project
}
