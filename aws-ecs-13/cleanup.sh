#!/usr/bin/env bash
# Remove the dedicated ECS Fargate exercise resources; keep shared resources.
set +x
set +v
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ~/aws-ecs-11/settings.local.sh
source ~/aws-ecs-12/settings.local.sh
source ./settings.local.sh
source ./save-settings.sh
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
for name in AWS_ACCOUNT_ID AWS_REGION CLUSTER_NAME SERVICE_NAME TASK_DEFINITION_ARN ALB_ARN TARGET_GROUP_ARN ALB_SG_ID ECS_SG_ID LOG_GROUP S3_BUCKET PREVIOUS_API_URL; do
  [[ -n "${!name:-}" ]] || { echo "Missing saved setting: $name" >&2; exit 1; }
done
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || exit 1
[[ "$(aws sts get-caller-identity --query Account --output text)" == "$AWS_ACCOUNT_ID" ]] || { echo 'Account mismatch.' >&2; exit 1; }
for name in TASK_DEFINITION_ARN ALB_ARN TARGET_GROUP_ARN; do
  [[ "${!name}" == "arn:aws:"*":${AWS_REGION}:${AWS_ACCOUNT_ID}:"* ]] || { echo "Unexpected ARN: $name" >&2; exit 1; }
done
[[ -f .generated/app.original.js && ! -L .generated/app.original.js ]] || { echo 'Missing original app.js backup; stop and review.' >&2; exit 1; }
backup_dir="$(mktemp -d ./cleanup-backup.XXXXXX)"
cp -p settings.local.sh "$backup_dir/settings.local.sh"
cp -p .generated/app.original.js "$backup_dir/app.before.js"
# Ignore only the explicit not-found code expected by each API.
remove_or_absent() {
  local code="$1"; shift
  if aws "$@" > "$backup_dir/last-result.json" 2> "$backup_dir/last-error.txt"; then
    return 0
  fi
  if grep -Fq "($code)" "$backup_dir/last-error.txt"; then return 0; fi
  cat "$backup_dir/last-error.txt" >&2
  return 1
}
aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --output json > "$backup_dir/service.json"
jq -e 'all(.failures[]?; .reason=="MISSING")' "$backup_dir/service.json" >/dev/null
# Dedicated cluster only: do not scale down other services or standalone tasks.
aws ecs list-services --cluster "$CLUSTER_NAME" --output json > "$backup_dir/services.json"
jq -e --arg name "$SERVICE_NAME" 'all(.serviceArns[]; (split("/")[-1])==$name)' "$backup_dir/services.json" >/dev/null || { echo 'Other services exist in the cluster.' >&2; exit 1; }
printf 'Account: %s\nRegion: %s\nCluster/service: %s / %s\nALB: %s\n' "$AWS_ACCOUNT_ID" "$AWS_REGION" "$CLUSTER_NAME" "$SERVICE_NAME" "$ALB_ARN"
echo 'Delete the exercise ECS service, ALB/listeners, target group, saved task revision, cluster, security groups and log group.'
echo 'Restore the previous S3 app.js and API_URL. Shared IAM/ECR/DynamoDB/S3 resources and DynamoDB sample data remain.'
echo 'Route 53 records are not changed. Remove any exercise Alias manually.'
read -r -p 'Type DELETE to continue: ' answer </dev/tty
[[ "$answer" == DELETE ]] || { echo 'Cancelled.'; exit 0; }
if jq -e 'any(.services[]; .status=="ACTIVE")' "$backup_dir/service.json" >/dev/null; then
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --desired-count 0 >/dev/null
  aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"
  aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" >/dev/null
fi
if jq -e 'any(.services[]; .status!="INACTIVE")' "$backup_dir/service.json" >/dev/null; then
  aws ecs wait services-inactive --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"
fi
aws ecs list-tasks --cluster "$CLUSTER_NAME" --output json > "$backup_dir/tasks.json"
jq -e '.taskArns | length==0' "$backup_dir/tasks.json" >/dev/null || { echo 'Tasks still exist; wait or review before resuming.' >&2; exit 1; }
aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN"
aws ecs deregister-task-definition --task-definition "$TASK_DEFINITION_ARN"
aws ecs delete-cluster --cluster "$CLUSTER_NAME" >/dev/null
# ENI release can lag behind ECS/ALB deletion. Retry dependency errors only.
for group in "$ECS_SG_ID" "$ALB_SG_ID"; do
  done_group=false
  for ((attempt=0; attempt<60; attempt++)); do
    if aws ec2 delete-security-group --group-id "$group" 2> "$backup_dir/last-error.txt"; then done_group=true; break; fi
    if grep -Fq '(InvalidGroup.NotFound)' "$backup_dir/last-error.txt"; then done_group=true; break; fi
    if ! grep -Fq '(DependencyViolation)' "$backup_dir/last-error.txt"; then cat "$backup_dir/last-error.txt" >&2; exit 1; fi
    sleep 5
  done
  [[ "$done_group" == true ]] || { cat "$backup_dir/last-error.txt" >&2; exit 1; }
done
remove_or_absent ResourceNotFoundException logs delete-log-group --log-group-name "$LOG_GROUP"
aws s3api put-object --bucket "$S3_BUCKET" --key app.js --body "$backup_dir/app.before.js" \
  --content-type 'application/javascript; charset=utf-8' --expected-bucket-owner "$AWS_ACCOUNT_ID" >/dev/null
API_URL="$PREVIOUS_API_URL"
save_settings_to ~/aws-ecs-11/settings.local.sh API_URL
# Archive generated files, so a fresh setup is not blocked by the old run markers.
mv -- .generated "$backup_dir/generated"
tmp="$(mktemp ./settings.local.sh.tmp.XXXXXX)"
sed -E '/^[[:space:]]*(export[[:space:]]+)?(VPC_ID|SUBNET_IDS|ALB_SG_ID|ECS_SG_ID|ALB_ARN|ALB_DNS|TARGET_GROUP_ARN|TASK_DEFINITION_ARN|IMAGE_DIGEST|IMAGE_URI|PREVIOUS_API_URL)[[:space:]]*=/d' settings.local.sh > "$tmp"
chmod 600 "$tmp"
mv -- "$tmp" settings.local.sh
printf 'Cleanup completed. Backups: %s\n' "$backup_dir"
echo 'DynamoDB sample data, shared resources and Route 53 records remain. Reload settings before continuing.'
