#!/usr/bin/env bash
# AWS CloudShell (Bash): bash cleanup.sh
# Deletes resources from part 1, including the former CLI-specific IAM policy.
set +x
set +v
set -euo pipefail
umask 077
cd "$(dirname -- "${BASH_SOURCE[0]}")"
source ./settings.local.sh
for name in AWS_ACCOUNT_ID AWS_REGION S3_BUCKET_PREFIX DYNAMODB_TABLE ECR_REPOSITORY EXECUTION_ROLE_NAME TASK_ROLE_NAME; do
  [[ -n "${!name:-}" && "${!name}" != *REPLACE_WITH* ]] || { printf 'Set %s first.\n' "$name" >&2; exit 1; }
done
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ && "$AWS_REGION" == ap-northeast-1 ]] || { echo 'Check account ID and region.' >&2; exit 1; }
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
CALLER_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
[[ "$CALLER_ACCOUNT" == "$AWS_ACCOUNT_ID" ]] || { echo 'AWS account mismatch.' >&2; exit 1; }
S3_BUCKET="${S3_BUCKET_PREFIX}-${AWS_ACCOUNT_ID}-${AWS_REGION}-an"
printf 'Account: %s\nRegion: %s\nS3: %s\nDynamoDB: %s\nECR: %s\nRoles: %s / %s\n' \
  "$AWS_ACCOUNT_ID" "$AWS_REGION" "$S3_BUCKET" "$DYNAMODB_TABLE" "$ECR_REPOSITORY" "$EXECUTION_ROLE_NAME" "$TASK_ROLE_NAME"
read -r -p 'Type DELETE to delete these part-1 resources: ' ANSWER </dev/tty
[[ "$ANSWER" == DELETE ]] || { echo 'Cancelled.'; exit 0; }
mkdir -p .generated
# Skip only known not-found errors; other failures must stop cleanup.
remove_if_present() {
  local missing="$1"
  shift
  if "$@" 2>.generated/cleanup-error.txt; then
    return 0
  elif grep -Eq "$missing" .generated/cleanup-error.txt; then
    echo 'Already absent; skipped.'
  else
    cat .generated/cleanup-error.txt >&2
    exit 1
  fi
}
for key in index.html app.js; do
  remove_if_present '\(NoSuchBucket\)|\(404\)|\(NotFound\)' \
    aws s3api delete-object --bucket "$S3_BUCKET" --key "$key" --expected-bucket-owner "$AWS_ACCOUNT_ID"
done
remove_if_present '\(NoSuchBucket\)|\(404\)|\(NotFound\)' \
  aws s3api delete-bucket --bucket "$S3_BUCKET" --expected-bucket-owner "$AWS_ACCOUNT_ID"
aws s3api wait bucket-not-exists --bucket "$S3_BUCKET" --expected-bucket-owner "$AWS_ACCOUNT_ID"
remove_if_present '\(RepositoryNotFoundException\)' \
  aws ecr delete-repository --registry-id "$AWS_ACCOUNT_ID" --repository-name "$ECR_REPOSITORY"
remove_if_present '\(ResourceNotFoundException\)' \
  aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --output json
aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE"
# Old CLI version used this inline policy. The new version does not create it.
remove_if_present '\(NoSuchEntity\)' \
  aws iam delete-role-policy --role-name "$TASK_ROLE_NAME" --policy-name ECS-Sample-DynamoDB
remove_if_present '\(NoSuchEntity\)' \
  aws iam detach-role-policy --role-name "$TASK_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess_v2
remove_if_present '\(NoSuchEntity\)' aws iam delete-role --role-name "$TASK_ROLE_NAME"
remove_if_present '\(NoSuchEntity\)' \
  aws iam detach-role-policy --role-name "$EXECUTION_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
remove_if_present '\(NoSuchEntity\)' aws iam delete-role --role-name "$EXECUTION_ROLE_NAME"
echo 'Part-1 cleanup completed. Local settings and files were retained.'
