# Terraform — infraestrutura do ToggleMaster

Toda a infraestrutura AWS da Fase 3, em módulos independentes.

```
terraform/
├── bootstrap/            # cria o bucket S3 do state (roda 1 vez, state local)
├── modules/
│   ├── network/          # VPC, subnets públicas/privadas, IGW, NAT, route tables
│   ├── eks/              # cluster EKS + node group (LabRole, IMDS hop limit 2)
│   ├── rds/              # 3x PostgreSQL + senhas no Secrets Manager
│   ├── elasticache/      # Redis
│   ├── dynamodb/         # tabela ToggleMasterAnalytics
│   ├── sqs/              # fila de eventos + DLQ
│   └── ecr/              # 5 repositórios togglemaster/<servico>
├── versions.tf           # providers + backend S3 (fiap-bucket-state-tf-grupo3)
├── main.tf               # chama os módulos
├── variables.tf
└── outputs.tf
```

## O que é criado

| Módulo | Recursos |
|---|---|
| network | VPC `10.0.0.0/16`, 2 subnets públicas, 2 privadas, Internet Gateway, 1 NAT Gateway, route tables |
| eks | Cluster `togglemaster` (K8s 1.34), node group 2× `t3.medium` (min 1, max 4) em subnet privada |
| rds | `togglemaster-auth-db`, `togglemaster-flags-db`, `togglemaster-targeting-db` (PostgreSQL 17, `db.t3.micro`) |
| elasticache | `togglemaster-redis` (`cache.t3.micro`) |
| dynamodb | `ToggleMasterAnalytics` (on-demand, chave `event_id`) |
| sqs | `togglemaster-events` + `togglemaster-events-dlq` |
| ecr | `togglemaster/{auth,flag,targeting,evaluation,analytics}-service` (scan on push, tags imutáveis) |

RDS e Redis só aceitam conexão vinda do security group do cluster EKS.

## Pré-requisitos

- Terraform >= 1.10
- AWS CLI com as credenciais do **AWS Academy** (Start Lab → AWS Details → AWS CLI → colar em `~/.aws/credentials`)
- Conferir a conta: `aws sts get-caller-identity`

## Como executar

```bash
# 1. Bucket do state (só na primeira vez; pule se o bucket já existir)
cd terraform/bootstrap
terraform init
terraform apply

# 2. Infra principal
cd ..
terraform init          # conecta no backend S3
terraform plan -out tfplan
terraform apply tfplan  # ~15-20 min (EKS e RDS são os mais lentos)

# 3. kubectl
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

Outputs úteis: `terraform output` (endpoints, URL da fila, URLs do ECR).
Senhas dos bancos: `terraform output -json database_urls` ou no Secrets Manager (`togglemaster/<servico>-db`).

## Destroy

```bash
# Se existir LoadBalancer criado pelo Kubernetes (ingress-nginx), apague antes,
# senão o NLB fica fora do Terraform e trava a remoção da VPC:
kubectl delete svc -n ingress-nginx ingress-nginx-controller --ignore-not-found

terraform destroy
```

O bucket do state (bootstrap) é mantido; para removê-lo: `cd bootstrap && terraform destroy`.

## Decisões

- **AWS Academy / LabRole**: o Academy não permite criar IAM. O cluster e os nodes usam a `LabRole` lida via `data "aws_iam_role"`. Não existe nenhum `aws_iam_role`/`aws_iam_policy` no código.
- **Credenciais AWS nos pods**: o launch template dos nodes usa `http_put_response_hop_limit = 2`. Assim os pods alcançam o IMDS e usam a LabRole para SQS/DynamoDB. O Secret `aws-creds` da Fase 2 (que expirava junto com a sessão do lab) deixa de existir.
- **Senhas sem texto plano**: `random_password` → Secrets Manager. A senha só existe no state, que fica no S3 privado, criptografado e versionado.
- **Nodes em subnet privada + 1 NAT Gateway**: é mais correto, e um único NAT economiza créditos. Para economizar mais, use `nodes_in_private_subnets = false`: os nodes vão para as subnets públicas e o NAT não é criado.
- **State**: backend S3 com `use_lockfile = true` (lock nativo no próprio bucket, sem DynamoDB).
- **Extended support do EKS**: `upgrade_policy = STANDARD` evita a cobrança extra de versões antigas.
- **Exceções do scan (Trivy)**: endpoint público do EKS, IP público nas subnets públicas e criptografia sem KMS próprio. Estão marcadas com `#trivy:ignore` e justificadas no código.
