#!/usr/bin/env bash
# AWS CloudShell (Bash): bash setup.sh
set +x
set +v
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ~/aws-ecs-11/settings.local.sh
source ~/aws-ecs-12/settings.local.sh
source ./settings.local.sh
source ./save-settings.sh
export AWS_DEFAULT_REGION="$AWS_REGION" AWS_REGION
export AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
mkdir -p .generated
trap 'echo "Stopped. Created resources remain. Review the last error and .generated/ before resuming." >&2' ERR

# Full-script checks only; individual article steps keep each operation short.
for tool in aws jq sed grep curl; do
  command -v "$tool" >/dev/null || { printf 'Required command: %s\n' "$tool" >&2; exit 1; }
done
for name in AWS_ACCOUNT_ID AWS_REGION EXECUTION_ROLE_NAME TASK_ROLE_NAME DYNAMODB_TABLE ECR_REPOSITORY IMAGE_TAG S3_BUCKET_PREFIX ALB_SG_NAME ECS_SG_NAME CLUSTER_NAME TASK_FAMILY SERVICE_NAME ALB_NAME TARGET_GROUP_NAME LOG_GROUP EXECUTION_ROLE_ARN TASK_ROLE_ARN ECR_URI S3_BUCKET WEBSITE_URL; do
  [[ -n "${!name:-}" && "${!name}" != *REPLACE_WITH* ]] || { printf 'Set %s in settings.local.sh\n' "$name" >&2; exit 1; }
done
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ && "$AWS_REGION" == ap-northeast-1 ]] || { echo 'Use a 12-digit account ID and Tokyo region.' >&2; exit 1; }
for name in ALB_SG_NAME ECS_SG_NAME CLUSTER_NAME TASK_FAMILY SERVICE_NAME ALB_NAME TARGET_GROUP_NAME; do
  [[ "${!name}" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || { printf 'Use a simple resource name: %s\n' "$name" >&2; exit 1; }
done
[[ "$ALB_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,31}$ && "$TARGET_GROUP_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,31}$ ]] || { echo 'ALB and target group names must be at most 32 letters, digits, or hyphens.' >&2; exit 1; }
[[ "$S3_BUCKET_PREFIX" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || { echo 'Use a simple S3 prefix without dots.' >&2; exit 1; }
[[ "$LOG_GROUP" =~ ^[a-zA-Z0-9/_.-]+$ ]] || { echo 'Use a simple log group name.' >&2; exit 1; }
[[ "$(aws sts get-caller-identity --query Account --output text)" == "$AWS_ACCOUNT_ID" ]] || { echo 'AWS account mismatch.' >&2; exit 1; }
[[ ! -e .generated/alb-sg-id.txt && ! -e .generated/app.before.js ]] || { echo 'Previous run files exist. Review the resources before restarting.' >&2; exit 1; }
aws iam get-role --role-name "$EXECUTION_ROLE_NAME" --output json > .generated/existing-execution-role.json
aws iam get-role --role-name "$TASK_ROLE_NAME" --output json > .generated/existing-task-role.json
aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --output json > .generated/existing-table.json
jq -e '.Table.TableStatus=="ACTIVE" and .Table.KeySchema==[{AttributeName:"id",KeyType:"HASH"}]' .generated/existing-table.json >/dev/null
aws dynamodb get-item --table-name "$DYNAMODB_TABLE" --key '{"id":{"S":"AzureToAWS"}}' \
  --consistent-read --output json > .generated/existing-item.json
jq -e 'has("Item") | not' .generated/existing-item.json >/dev/null || { echo 'Sample item already exists; it will not be replaced.' >&2; exit 1; }
aws ecr describe-images --registry-id "$AWS_ACCOUNT_ID" --repository-name "$ECR_REPOSITORY" \
  --image-ids "imageTag=$IMAGE_TAG" --output json > .generated/existing-image.json
aws s3api head-object --bucket "$S3_BUCKET" \
  --key app.js --expected-bucket-owner "$AWS_ACCOUNT_ID" > .generated/existing-app.json


# STEP 1: デフォルトVPCを取得する
VPC_ID="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)"
save_settings VPC_ID
printf 'VPC_ID=%s\n' "$VPC_ID"

# STEP 2: デフォルトサブネットを取得する
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" Name=default-for-az,Values=true \
  --output json > .generated/subnets.json
read -r -a SUBNET_IDS <<< "$(jq -r '[.Subnets[].SubnetId] | join(" ")' .generated/subnets.json)"
save_settings SUBNET_IDS
jq '.Subnets[] | {SubnetId, AvailabilityZone, AvailableIpAddressCount}' .generated/subnets.json

[[ "$VPC_ID" == vpc-* ]] || { echo 'Default VPC not found.' >&2; exit 1; }
jq -e '([.Subnets[].AvailabilityZone] | unique | length) >= 2 and all(.Subnets[]; .AvailableIpAddressCount >= 8)' .generated/subnets.json >/dev/null || { echo 'At least two default subnets in distinct AZs with eight free IPs are required.' >&2; exit 1; }
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --output json > .generated/routes.json
for subnet in "${SUBNET_IDS[@]}"; do
  jq -e --arg subnet "$subnet" '
    ([.RouteTables[] | select(any(.Associations[]?; .SubnetId==$subnet))] |
      if length>0 then . else empty end) as $explicit |
    any($explicit[].Routes[]?; .DestinationCidrBlock=="0.0.0.0/0" and .State=="active" and (.GatewayId // "" | startswith("igw-")))
  ' .generated/routes.json >/dev/null ||
  jq -e --arg subnet "$subnet" '
    ([.RouteTables[] | select(any(.Associations[]?; .SubnetId==$subnet))] | length)==0 and
    any(.RouteTables[]; any(.Associations[]?; .Main==true) and
      any(.Routes[]?; .DestinationCidrBlock=="0.0.0.0/0" and .State=="active" and (.GatewayId // "" | startswith("igw-"))))
  ' .generated/routes.json >/dev/null || { echo "No public default route for $subnet" >&2; exit 1; }
done
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$ALB_SG_NAME,$ECS_SG_NAME" --output json > .generated/existing-sg.json
jq -e '.SecurityGroups | length==0' .generated/existing-sg.json >/dev/null || { echo 'Security group names already exist.' >&2; exit 1; }
aws elbv2 describe-load-balancers --output json > .generated/existing-albs.json
jq -e --arg name "$ALB_NAME" 'all(.LoadBalancers[]; .LoadBalancerName!=$name)' .generated/existing-albs.json >/dev/null || { echo 'ALB name already exists.' >&2; exit 1; }
aws elbv2 describe-target-groups --output json > .generated/existing-targets.json
jq -e --arg name "$TARGET_GROUP_NAME" 'all(.TargetGroups[]; .TargetGroupName!=$name)' .generated/existing-targets.json >/dev/null || { echo 'Target group name already exists.' >&2; exit 1; }
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --output json > .generated/existing-cluster.json
jq -e 'all(.clusters[]; .status=="INACTIVE") and all(.failures[]; .reason=="MISSING")' .generated/existing-cluster.json >/dev/null || { echo 'Cluster already exists or cannot be checked.' >&2; exit 1; }
aws ecs list-task-definitions --family-prefix "$TASK_FAMILY" --status ACTIVE --output json > .generated/existing-tasks.json
jq -e --arg family "$TASK_FAMILY" 'all(.taskDefinitionArns[]; (split("/")[-1] | split(":")[0])!=$family)' .generated/existing-tasks.json >/dev/null || { echo 'Task definition family already exists.' >&2; exit 1; }
aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --output json > .generated/existing-logs.json
jq -e --arg name "$LOG_GROUP" 'all(.logGroups[]; .logGroupName!=$name)' .generated/existing-logs.json >/dev/null || { echo 'Log group already exists.' >&2; exit 1; }

# STEP 3: ALB用セキュリティグループを作成する
ALB_SG_ID="$(aws ec2 create-security-group \
  --group-name "$ALB_SG_NAME" --description 'HTTP access to sample ALB' \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$ALB_SG_NAME}]" \
  --query GroupId --output text)"
save_settings ALB_SG_ID
printf '%s\n' "$ALB_SG_ID" > .generated/alb-sg-id.txt
printf 'ALB_SG_ID=%s\n' "$ALB_SG_ID"

# STEP 4: ALBへHTTP通信を許可する
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# STEP 5: ECS用セキュリティグループを作成する
ECS_SG_ID="$(aws ec2 create-security-group \
  --group-name "$ECS_SG_NAME" --description 'Sample ECS tasks' \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$ECS_SG_NAME}]" \
  --query GroupId --output text)"
save_settings ECS_SG_ID
printf '%s\n' "$ECS_SG_ID" > .generated/ecs-sg-id.txt
printf 'ECS_SG_ID=%s\n' "$ECS_SG_ID"

# STEP 6: ALBからECSへの通信を許可する
aws ec2 authorize-security-group-ingress --group-id "$ECS_SG_ID" \
  --protocol tcp --port 8080 --source-group "$ALB_SG_ID"

# STEP 7: ターゲットグループを作成する
TARGET_GROUP_ARN="$(aws elbv2 create-target-group \
  --name "$TARGET_GROUP_NAME" --protocol HTTP --port 8080 \
  --vpc-id "$VPC_ID" --target-type ip --health-check-path /health \
  --query 'TargetGroups[0].TargetGroupArn' --output text)"
save_settings TARGET_GROUP_ARN
printf '%s\n' "$TARGET_GROUP_ARN" > .generated/target-group-arn.txt
printf 'TARGET_GROUP_ARN=%s\n' "$TARGET_GROUP_ARN"

# STEP 8: ALBを作成する
aws elbv2 create-load-balancer --name "$ALB_NAME" \
  --type application --scheme internet-facing --ip-address-type ipv4 \
  --security-groups "$ALB_SG_ID" --subnets "${SUBNET_IDS[@]}" \
  --output json > .generated/alb.json
ALB_ARN="$(jq -r '.LoadBalancers[0].LoadBalancerArn' .generated/alb.json)"
save_settings ALB_ARN
ALB_DNS="$(jq -r '.LoadBalancers[0].DNSName' .generated/alb.json)"
save_settings ALB_DNS
printf 'ALB_DNS=%s\n' "$ALB_DNS"

# STEP 9: ALBの作成完了を待つ
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

# STEP 10: HTTPリスナーを作成する
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TARGET_GROUP_ARN" \
  --output json > .generated/listener.json
jq '.Listeners[] | {ListenerArn, Port, DefaultActions}' .generated/listener.json

# STEP 11: クラスターを作成する
aws ecs create-cluster --cluster-name "$CLUSTER_NAME" \
  --output json > .generated/cluster.json
jq '.cluster | {clusterName, clusterArn, status}' .generated/cluster.json

# STEP 12: ②でPushしたイメージを取得する
IMAGE_DIGEST="$(aws ecr describe-images --registry-id "$AWS_ACCOUNT_ID" \
  --repository-name "$ECR_REPOSITORY" --image-ids "imageTag=$IMAGE_TAG" \
  --query 'imageDetails[0].imageDigest' --output text)"
save_settings IMAGE_DIGEST
IMAGE_URI="$ECR_URI@$IMAGE_DIGEST"
save_settings IMAGE_URI
printf 'IMAGE_URI=%s\n' "$IMAGE_URI"

# STEP 13: ロググループを作成する
aws logs create-log-group --log-group-name "$LOG_GROUP"

# STEP 14: タスク定義のJSONへ設定値を反映する
jq --arg family "$TASK_FAMILY" --arg taskRole "$TASK_ROLE_ARN" \
  --arg executionRole "$EXECUTION_ROLE_ARN" --arg image "$IMAGE_URI" \
  --arg table "$DYNAMODB_TABLE" --arg region "$AWS_REGION" --arg logs "$LOG_GROUP" \
  '.family=$family | .taskRoleArn=$taskRole | .executionRoleArn=$executionRole |
   .containerDefinitions[0].image=$image |
   .containerDefinitions[0].environment=[{name:"DYNAMODB_TABLE",value:$table},{name:"AWS_REGION",value:$region}] |
   .containerDefinitions[0].logConfiguration.options["awslogs-group"]=$logs |
   .containerDefinitions[0].logConfiguration.options["awslogs-region"]=$region' \
  task-definition.template.json > .generated/task-definition.json
jq '{family, cpu, memory, containerDefinitions}' .generated/task-definition.json

# STEP 15: タスク定義を登録する
TASK_DEFINITION_ARN="$(aws ecs register-task-definition \
  --cli-input-json file://.generated/task-definition.json \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
save_settings TASK_DEFINITION_ARN
printf '%s\n' "$TASK_DEFINITION_ARN" > .generated/task-definition-arn.txt
printf 'TASK_DEFINITION_ARN=%s\n' "$TASK_DEFINITION_ARN"

# STEP 16: サービスのネットワーク設定を作る
jq -n --argjson subnets "$(printf '%s\n' "${SUBNET_IDS[@]}" | jq -R . | jq -s .)" \
  --arg sg "$ECS_SG_ID" \
  '{awsvpcConfiguration:{subnets:$subnets,securityGroups:[$sg],assignPublicIp:"ENABLED"}}' \
  > .generated/network-configuration.json

# STEP 17: Fargateサービスを作成する
aws ecs create-service --cluster "$CLUSTER_NAME" --service-name "$SERVICE_NAME" \
  --task-definition "$TASK_DEFINITION_ARN" --launch-type FARGATE --desired-count 1 \
  --network-configuration file://.generated/network-configuration.json \
  --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=webapi,containerPort=8080" \
  --health-check-grace-period-seconds 60 --availability-zone-rebalancing ENABLED \
  --output json > .generated/service.json
jq '.service | {serviceName, status, desiredCount, runningCount}' .generated/service.json

# STEP 18: サービスの起動完了を待つ
aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"

# STEP 19: ターゲットの状態を確認する
aws elbv2 describe-target-health --target-group-arn "$TARGET_GROUP_ARN" \
  --query 'TargetHealthDescriptions[].{IP:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table

# STEP 20: APIの接続先を設定する
API_URL="http://$ALB_DNS/api"
save_settings_to ~/aws-ecs-11/settings.local.sh API_URL
printf '%s\n' "$API_URL" > .generated/api-url.txt
printf 'API_URL=%s\n' "$API_URL"

# STEP 21: ヘルスチェックへアクセスする
curl --fail --show-error --silent --retry 5 --retry-all-errors --retry-delay 3 \
  --connect-timeout 10 --max-time 30 "http://$ALB_DNS/health"
printf '\n'

# STEP 22: 項目追加前のAPI応答を確認する
curl --fail --show-error --silent --retry 5 --retry-all-errors --retry-delay 3 \
  --connect-timeout 10 --max-time 30 "$API_URL" | jq .

# STEP 23: サンプル項目を追加する
aws dynamodb put-item --table-name "$DYNAMODB_TABLE" \
  --item file://dynamodb-item.json --condition-expression 'attribute_not_exists(id)'

# STEP 24: 登録した項目を参照する
aws dynamodb get-item --table-name "$DYNAMODB_TABLE" \
  --key '{"id":{"S":"AzureToAWS"}}' --consistent-read --output json

# STEP 25: APIを2回呼び出してカウントを確認する
curl --fail --show-error --silent --connect-timeout 10 --max-time 30 \
  "$API_URL" > .generated/api-first.json
curl --fail --show-error --silent --connect-timeout 10 --max-time 30 \
  "$API_URL" > .generated/api-second.json
jq '{source, title, message, accessCount}' .generated/api-first.json .generated/api-second.json
jq -e -s '.[0].source == "DynamoDB" and .[1].source == "DynamoDB" and
  (.[0].accessCount | type) == "number" and (.[1].accessCount | type) == "number" and
  .[1].accessCount > .[0].accessCount' .generated/api-first.json .generated/api-second.json

# STEP 26: 配置済みJavaScriptを取得する
aws s3api get-object --bucket "$S3_BUCKET" --key app.js \
  --expected-bucket-owner "$AWS_ACCOUNT_ID" .generated/app.before.js

# STEP 27: APIのURLを置き換える
test "$(grep -Ec '^[[:space:]]*const API_URL[[:space:]]*=' .generated/app.before.js)" = 1
sed "s|^[[:space:]]*const API_URL[[:space:]]*=.*$|const API_URL = \"$API_URL\";|" \
  .generated/app.before.js > .generated/app.js
grep '^const API_URL' .generated/app.js

# STEP 28: app.jsだけを再アップロードする
aws s3api put-object --bucket "$S3_BUCKET" --key app.js --body .generated/app.js \
  --content-type 'application/javascript; charset=utf-8' \
  --expected-bucket-owner "$AWS_ACCOUNT_ID"
printf '%s\n' "$WEBSITE_URL" > .generated/website-url.txt
printf 'Web画面: %s\nAPI: %s\n' "$WEBSITE_URL" "$API_URL"
jq -n --arg account "$AWS_ACCOUNT_ID" --arg region "$AWS_REGION" \
  --arg cluster "$CLUSTER_NAME" --arg service "$SERVICE_NAME" --arg task "$TASK_DEFINITION_ARN" \
  --arg alb "$ALB_ARN" --arg target "$TARGET_GROUP_ARN" --arg albSg "$ALB_SG_ID" --arg ecsSg "$ECS_SG_ID" \
  --arg logGroup "$LOG_GROUP" --arg api "$API_URL" --arg website "$WEBSITE_URL" \
  '{accountId:$account,region:$region,cluster:$cluster,service:$service,taskDefinition:$task,albArn:$alb,targetGroupArn:$target,albSecurityGroup:$albSg,ecsSecurityGroup:$ecsSg,logGroup:$logGroup,apiUrl:$api,websiteUrl:$website}' \
  > .generated/resources.json
echo 'Construction and API checks completed. Open the website URL in your browser.'
