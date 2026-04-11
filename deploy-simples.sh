#!/bin/bash
set -e

COMMIT_HASH=${1:-$(git rev-parse --short HEAD)}
REGION="us-east-1"
ACCOUNT_ID="633740007402"
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/bia"
IMAGE_URI="${ECR_REPO}:${COMMIT_HASH}"
TASK_FAMILY="task-def-bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"

echo "==> Deploy: $IMAGE_URI"

# Login ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# Build e push
docker build -t $IMAGE_URI .
docker push $IMAGE_URI

# Registra nova task definition com a nova imagem
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION \
  --query 'taskDefinition' --output json)

NEW_TASK_DEF=$(echo $TASK_DEF | python3 -c "
import json, sys
td = json.load(sys.stdin)
td['containerDefinitions'][0]['image'] = '${IMAGE_URI}'
for key in ['taskDefinitionArn','revision','status','requiresAttributes','registeredAt','registeredBy','compatibilities']:
    td.pop(key, None)
print(json.dumps(td))
")

NEW_REVISION=$(aws ecs register-task-definition --region $REGION \
  --cli-input-json "$NEW_TASK_DEF" \
  --query 'taskDefinition.taskDefinitionArn' --output text)

echo "==> Nova task definition: $NEW_REVISION"

# Atualiza o service
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition $NEW_REVISION \
  --region $REGION \
  --query 'service.deployments[0].{status:status,taskDef:taskDefinition}' \
  --output table

echo "==> Deploy iniciado com sucesso!"
