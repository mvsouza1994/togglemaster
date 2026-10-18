output "repository_urls" {
  description = "servico => URL do repositorio"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "registry" {
  description = "<conta>.dkr.ecr.<regiao>.amazonaws.com"
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}
