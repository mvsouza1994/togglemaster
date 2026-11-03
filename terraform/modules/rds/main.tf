resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.subnet_ids

  tags = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "PostgreSQL acessivel somente a partir do cluster EKS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-rds" })
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL a partir do EKS"
}

resource "random_password" "db" {
  for_each = var.databases

  length  = 32
  special = false
}

resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier     = "${var.name}-${each.key}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = each.value
  username = var.master_username
  password = random_password.db[each.key].result

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  auto_minor_version_upgrade = true

  tags = merge(var.tags, { Service = each.key })
}

resource "aws_secretsmanager_secret" "db" {
  for_each = var.databases

  name        = "${var.name}/${each.key}-db"
  description = "Credenciais do PostgreSQL do ${each.key}-service"

  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  for_each = var.databases

  secret_id = aws_secretsmanager_secret.db[each.key].id
  secret_string = jsonencode({
    username     = var.master_username
    password     = random_password.db[each.key].result
    host         = aws_db_instance.this[each.key].address
    port         = aws_db_instance.this[each.key].port
    dbname       = each.value
    DATABASE_URL = "postgres://${var.master_username}:${random_password.db[each.key].result}@${aws_db_instance.this[each.key].endpoint}/${each.value}?sslmode=require"
  })
}
