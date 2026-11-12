#!/usr/bin/env bash
set +x
set +v
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./settings.local.sh
source ./save-settings.sh
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
mkdir -p .generated

[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ && "$AWS_REGION" == ap-northeast-1 ]] || { echo 'Check account ID and Tokyo region.' >&2; exit 1; }
[[ "$(aws sts get-caller-identity --query Account --output text)" == "$AWS_ACCOUNT_ID" ]] || { echo 'AWS account mismatch.' >&2; exit 1; }
[[ "$IAM_USER_NAME" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo 'Use a simple IAM user name.' >&2; exit 1; }
aws iam list-users --output json > .generated/existing-users.json
jq -e --arg user "$IAM_USER_NAME" 'all(.Users[]; .UserName != $user)' .generated/existing-users.json >/dev/null || { echo 'IAM user already exists. Use the individual steps for an existing user.' >&2; exit 1; }
EXECUTION_ROLE_ARN="$(aws iam get-role --role-name "$EXECUTION_ROLE_NAME" --query Role.Arn --output text)"
save_settings EXECUTION_ROLE_ARN
TASK_ROLE_ARN="$(aws iam get-role --role-name "$TASK_ROLE_NAME" --query Role.Arn --output text)"
save_settings TASK_ROLE_ARN
aws ecr describe-repositories --registry-id "$AWS_ACCOUNT_ID" --repository-names "$ECR_REPOSITORY" --output json > .generated/ecr.json

aws iam create-user --user-name "$IAM_USER_NAME" --output json > .generated/iam-user.json
IAM_USER_ARN="$(jq -r '.User.Arn' .generated/iam-user.json)"
save_settings IAM_USER_ARN
printf 'IAM_USER_ARN=%s\n' "$IAM_USER_ARN"

aws iam attach-user-policy --user-name "$IAM_USER_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

aws iam attach-user-policy --user-name "$IAM_USER_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

jq -n --arg executionRole "$EXECUTION_ROLE_ARN" --arg taskRole "$TASK_ROLE_ARN" \
  '{Version:"2012-10-17",Statement:[{Effect:"Allow",Action:"iam:PassRole",Resource:[$taskRole,$executionRole]}]}' \
  > .generated/iam-passrole-ecs.json

aws iam put-user-policy --user-name "$IAM_USER_NAME" --policy-name IAM-PassRole-ECS \
  --policy-document file://.generated/iam-passrole-ecs.json

aws iam list-attached-user-policies --user-name "$IAM_USER_NAME" --output table
aws iam get-user-policy --user-name "$IAM_USER_NAME" --policy-name IAM-PassRole-ECS --output json

echo 'IAM setup completed. Create an access key and register GitHub Secrets manually.'
