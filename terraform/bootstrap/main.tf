# Bootstrap: cria o bucket S3 que guarda o state remoto do projeto principal.
# Roda UMA vez, com state local (o bucket ainda nao existe para guardar o proprio state).
#
#   cd terraform/bootstrap && terraform init && terraform apply
#
# Se o bucket ja existir (ex.: criado por outro membro do grupo), pule este passo.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type    = string
  default = "fiap-bucket-state-tf-grupo3"
}

resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  # Permite o destroy mesmo com versoes antigas do state dentro (ambiente de lab).
  force_destroy = true

  tags = {
    Project   = "togglemaster"
    ManagedBy = "terraform"
  }
}

# Versionamento: permite recuperar um state corrompido ou apagado por engano.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256) e suficiente para o lab; KMS proprio teria custo por requisicao.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# O state contem senhas geradas: o bucket nunca pode ser publico.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  value = aws_s3_bucket.state.bucket
}
