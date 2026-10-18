output "endpoints" {
  description = "servico => host:porta"
  value       = { for k, db in aws_db_instance.this : k => db.endpoint }
}

output "secret_arns" {
  description = "servico => ARN do secret com as credenciais"
  value       = { for k, s in aws_secretsmanager_secret.db : k => s.arn }
}

output "database_urls" {
  description = "servico => DATABASE_URL (sensivel)"
  value = {
    for k, db in aws_db_instance.this :
    k => "postgres://${db.username}:${random_password.db[k].result}@${db.endpoint}/${db.db_name}?sslmode=require"
  }
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.this.id
}
