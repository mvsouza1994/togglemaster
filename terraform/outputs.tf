output "region" {
  value = var.region
}

# ---------- Rede ----------

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

# ---------- EKS ----------

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

# ---------- Dados ----------

output "rds_endpoints" {
  value = module.rds.endpoints
}

output "rds_secret_arns" {
  description = "Credenciais de cada banco no Secrets Manager"
  value       = module.rds.secret_arns
}

output "database_urls" {
  description = "terraform output -json database_urls (sensivel)"
  value       = module.rds.database_urls
  sensitive   = true
}

output "redis_url" {
  value = module.elasticache.redis_url
}

output "dynamodb_table" {
  value = module.dynamodb.table_name
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

# ---------- ECR ----------

output "ecr_registry" {
  value = module.ecr.registry
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}
