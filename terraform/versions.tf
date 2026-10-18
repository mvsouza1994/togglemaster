terraform {
  required_version = ">= 1.10" # use_lockfile no backend S3 exige 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State remoto no S3. O bucket e criado antes por terraform/bootstrap.
  # use_lockfile cria um .tflock no proprio bucket (lock nativo, sem DynamoDB).
  backend "s3" {
    bucket       = "fiap-bucket-state-tf-grupo3"
    key          = "togglemaster/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
