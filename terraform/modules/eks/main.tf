# Cluster EKS + node group gerenciado.
# AWS Academy: nao e permitido criar IAM. Cluster e nodes usam a LabRole existente (role_arn).

# Excecoes aceitas no lab (documentadas no README):
# - endpoint publico: kubectl e demo a partir da maquina do grupo (restrinja com public_access_cidrs)
# - sem criptografia de secrets com KMS proprio: evita custo/gestao de chave no Academy
#trivy:ignore:AWS-0039
#trivy:ignore:AWS-0040
#trivy:ignore:AWS-0041
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.role_arn

  vpc_config {
    subnet_ids              = var.cluster_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Quem roda o apply (a sessao da LabRole) vira admin do cluster.
    bootstrap_cluster_creator_admin_permissions = true
  }

  # STANDARD evita a cobranca de "extended support" (US$ 0,60/h) em versoes antigas.
  upgrade_policy {
    support_type = "STANDARD"
  }

  enabled_cluster_log_types = var.cluster_log_types

  tags = var.tags
}

# Launch template do node group.
# hop limit 2 permite que os PODS alcancem o IMDS do node e usem as credenciais da LabRole
# (SQS / DynamoDB) sem Secret com access key. Resolve o "aws-creds" da Fase 2, que expirava.
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node" })
  }

  tags = var.tags
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = var.role_arn
  subnet_ids      = var.node_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  tags = var.tags

  # O cluster autoscaler / HPA podem mudar o desired_size; o Terraform nao deve brigar com isso.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
