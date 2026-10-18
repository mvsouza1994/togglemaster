# Um repositorio ECR por microsservico: <prefixo>/<servico> (ex.: togglemaster/auth-service).
# O CI faz push com a tag v1.0.0-<sha>.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${var.prefix}/${each.value}"
  image_tag_mutability = "IMMUTABLE" # uma tag = uma imagem (o CI usa v1.0.0-<sha>, nunca "latest")
  force_delete         = true        # destroy remove o repo mesmo com imagens (lab)

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Service = each.value })
}

# Mantem so as ultimas N imagens para nao acumular custo de armazenamento.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter apenas as ultimas ${var.keep_last_images} imagens"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_images
      }
      action = { type = "expire" }
    }]
  })
}
