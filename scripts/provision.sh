#!/bin/bash
# Provisiona TODA a infra AWS do ToggleMaster do zero.
# Reproduz exatamente o que foi feito em 2026-08-17.
#
# Pre-requisitos: lab do AWS Academy iniciado e ~/.aws/credentials atualizado.
# Tempo total: ~20 min (a maior parte esperando EKS e RDS).
#
# Estrategia: dispara os recursos LENTOS primeiro e so espera no final.
set -uo pipefail

REGION=us-east-1
CLUSTER=togglemaster
DB_PASS="${DB_PASS:-ToggleMaster2026Lab}"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
LABROLE="arn:aws:iam::${ACCOUNT}:role/LabRole"
echo "conta: $ACCOUNT | role: $LABROLE"

VPC=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" "Name=default-for-az,Values=true" \
          --query "sort_by(Subnets,&AvailabilityZone)[0:3].SubnetId" --output text)
S1=$(echo $SUBNETS | cut -d' ' -f1); S2=$(echo $SUBNETS | cut -d' ' -f2); S3=$(echo $SUBNETS | cut -d' ' -f3)
echo "vpc: $VPC | subnets: $S1 $S2 $S3"

echo "===== Security group ====="
SG=$(aws ec2 create-security-group --group-name togglemaster-data \
      --description "ToggleMaster data stores" --vpc-id $VPC --query GroupId --output text 2>/dev/null) \
  || SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=togglemaster-data" \
          --query "SecurityGroups[0].GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 5432 --cidr 172.31.0.0/16 >/dev/null 2>&1
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 6379 --cidr 172.31.0.0/16 >/dev/null 2>&1
echo "sg: $SG"

echo "===== EKS (o mais lento, dispara primeiro) ====="
aws eks create-cluster --name $CLUSTER --role-arn "$LABROLE" \
  --resources-vpc-config "subnetIds=$S1,$S2,$S3,endpointPublicAccess=true,endpointPrivateAccess=true" \
  --access-config "authenticationMode=API_AND_CONFIG_MAP,bootstrapClusterCreatorAdminPermissions=true" \
  --query "cluster.status" --output text

echo "===== RDS x3 ====="
aws rds create-db-subnet-group --db-subnet-group-name togglemaster-db-subnets \
  --db-subnet-group-description "ToggleMaster RDS subnets" --subnet-ids $S1 $S2 $S3 >/dev/null 2>&1
for pair in "auth-db:auth_db" "flags-db:flags_db" "targeting-db:targeting_db"; do
  aws rds create-db-instance --db-instance-identifier "${pair%%:*}" --db-name "${pair##*:}" \
    --db-instance-class db.t3.micro --engine postgres \
    --master-username postgres --master-user-password "$DB_PASS" \
    --allocated-storage 20 --storage-type gp2 --no-multi-az \
    --backup-retention-period 0 --no-publicly-accessible \
    --db-subnet-group-name togglemaster-db-subnets --vpc-security-group-ids $SG \
    --query "DBInstance.DBInstanceIdentifier" --output text
done

echo "===== ElastiCache ====="
aws elasticache create-cache-subnet-group --cache-subnet-group-name togglemaster-cache-subnets \
  --cache-subnet-group-description "ToggleMaster cache subnets" --subnet-ids $S1 $S2 $S3 >/dev/null 2>&1
aws elasticache create-cache-cluster --cache-cluster-id togglemaster-redis \
  --engine redis --cache-node-type cache.t3.micro --num-cache-nodes 1 \
  --cache-subnet-group-name togglemaster-cache-subnets --security-group-ids $SG \
  --query "CacheCluster.CacheClusterId" --output text

echo "===== DynamoDB / SQS / ECR (instantaneos) ====="
aws dynamodb create-table --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --query "TableDescription.TableStatus" --output text
aws sqs create-queue --queue-name togglemaster-events --query QueueUrl --output text
for r in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr create-repository --repository-name $r --query "repository.repositoryUri" --output text 2>/dev/null
done

echo "===== Build + push das imagens (enquanto o EKS provisiona) ====="
REG="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
( cd "$(dirname "$0")/.." && docker compose build )
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REG
for s in auth flag targeting evaluation analytics; do
  docker tag togglemaster/${s}-service:v1 $REG/${s}-service:v1
  docker push $REG/${s}-service:v1 | tail -1
done

echo "===== Esperando o EKS ficar ativo ====="
aws eks wait cluster-active --name $CLUSTER --region $REGION
echo "cluster ativo"

echo "===== Node group ====="
aws eks create-nodegroup --cluster-name $CLUSTER --nodegroup-name ng-togglemaster \
  --node-role "$LABROLE" --subnets $S1 $S2 $S3 \
  --instance-types t3.medium --disk-size 20 \
  --scaling-config minSize=1,maxSize=4,desiredSize=2 \
  --ami-type AL2023_x86_64_STANDARD --query "nodegroup.status" --output text
aws eks wait nodegroup-active --cluster-name $CLUSTER --nodegroup-name ng-togglemaster --region $REGION

aws eks update-kubeconfig --name $CLUSTER --region $REGION
kubectl wait --for=condition=Ready nodes --all --timeout=420s

echo ""
echo "===== INFRA PRONTA ====="
echo "Proximos passos:  bash scripts/deploy.sh"
