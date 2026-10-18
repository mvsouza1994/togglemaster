#!/bin/bash
# Destroi TODOS os recursos AWS do ToggleMaster.
#
# A ORDEM IMPORTA: o Service LoadBalancer do ingress-nginx precisa sair ANTES do
# cluster. Se o cluster for deletado primeiro, o NLB fica orfao consumindo o
# orcamento do lab e so da pra achar vasculhando o console de EC2.
set -uo pipefail

REGION=us-east-1
CLUSTER=togglemaster

echo "===== 1. Ingress e NLB ====="
kubectl delete ingress --all -A --ignore-not-found 2>/dev/null
kubectl delete svc ingress-nginx-controller -n ingress-nginx --ignore-not-found 2>/dev/null
echo "aguardando o NLB ser removido..."
sleep 60

echo "===== 2. Node group ====="
aws eks delete-nodegroup --cluster-name $CLUSTER --nodegroup-name ng-togglemaster --region $REGION >/dev/null 2>&1
aws eks wait nodegroup-deleted --cluster-name $CLUSTER --nodegroup-name ng-togglemaster --region $REGION 2>/dev/null
echo "node group removido"

echo "===== 3. Cluster EKS ====="
aws eks delete-cluster --name $CLUSTER --region $REGION >/dev/null 2>&1
aws eks wait cluster-deleted --name $CLUSTER --region $REGION 2>/dev/null
echo "cluster removido"

echo "===== 4. RDS (3 instancias) ====="
for db in auth-db flags-db targeting-db; do
  aws rds delete-db-instance --db-instance-identifier $db --skip-final-snapshot \
    --delete-automated-backups --region $REGION >/dev/null 2>&1 && echo "  $db: delecao iniciada"
done
for db in auth-db flags-db targeting-db; do
  aws rds wait db-instance-deleted --db-instance-identifier $db --region $REGION 2>/dev/null
  echo "  $db: removido"
done
aws rds delete-db-subnet-group --db-subnet-group-name togglemaster-db-subnets --region $REGION >/dev/null 2>&1

echo "===== 5. ElastiCache ====="
aws elasticache delete-cache-cluster --cache-cluster-id togglemaster-redis --region $REGION >/dev/null 2>&1
aws elasticache wait cache-cluster-deleted --cache-cluster-id togglemaster-redis --region $REGION 2>/dev/null
aws elasticache delete-cache-subnet-group --cache-subnet-group-name togglemaster-cache-subnets --region $REGION >/dev/null 2>&1
echo "elasticache removido"

echo "===== 6. DynamoDB ====="
aws dynamodb delete-table --table-name ToggleMasterAnalytics --region $REGION >/dev/null 2>&1 && echo "tabela removida"

echo "===== 7. SQS ====="
for q in togglemaster-events togglemaster-events-local; do
  QURL=$(aws sqs get-queue-url --queue-name $q --region $REGION --query QueueUrl --output text 2>/dev/null)
  [ -n "${QURL:-}" ] && aws sqs delete-queue --queue-url "$QURL" --region $REGION && echo "  fila $q removida"
done

echo "===== 8. ECR ====="
for r in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr delete-repository --repository-name $r --force --region $REGION >/dev/null 2>&1 && echo "  $r removido"
done

echo "===== 9. Security group ====="
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=togglemaster-data" \
      --query "SecurityGroups[0].GroupId" --output text --region $REGION 2>/dev/null)
[ "${SG:-None}" != "None" ] && aws ec2 delete-security-group --group-id "$SG" --region $REGION >/dev/null 2>&1 && echo "  $SG removido"

echo ""
echo "===== VERIFICACAO FINAL (tudo deve vir vazio) ====="
echo "-- load balancers:"; aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[].LoadBalancerName" --output text 2>/dev/null
echo "-- clusters EKS:";   aws eks list-clusters --region $REGION --query "clusters" --output text 2>/dev/null
echo "-- RDS:";            aws rds describe-db-instances --region $REGION --query "DBInstances[].DBInstanceIdentifier" --output text 2>/dev/null
echo "-- ElastiCache:";    aws elasticache describe-cache-clusters --region $REGION --query "CacheClusters[].CacheClusterId" --output text 2>/dev/null
echo "-- ECR:";            aws ecr describe-repositories --region $REGION --query "repositories[].repositoryName" --output text 2>/dev/null
echo "-- EC2 rodando:";    aws ec2 describe-instances --region $REGION --filters "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null
