#!/usr/bin/env bash
# Delete the dedicated part-2 IAM user and its access keys. No shared resources.
set +x
set +v
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ~/aws-ecs-11/settings.local.sh
source ./settings.local.sh
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo 'Invalid AWS account ID.' >&2; exit 1; }
[[ "$IAM_USER_NAME" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo 'Invalid IAM user name.' >&2; exit 1; }
[[ "${IAM_USER_ARN:-}" == "arn:aws:iam::${AWS_ACCOUNT_ID}:user/${IAM_USER_NAME}" ]] || { echo 'Load the saved part-2 IAM user ARN first.' >&2; exit 1; }
[[ "$(aws sts get-caller-identity --query Account --output text)" == "$AWS_ACCOUNT_ID" ]] || { echo 'AWS account mismatch.' >&2; exit 1; }
current_arn="$(aws iam get-user --user-name "$IAM_USER_NAME" --query User.Arn --output text)"
[[ "$current_arn" == "$IAM_USER_ARN" ]] || { echo 'IAM user does not match saved settings.' >&2; exit 1; }
printf 'Account: %s\nIAM user: %s\nAll access keys of this user will be deleted.\n' "$AWS_ACCOUNT_ID" "$IAM_USER_NAME"
read -r -p 'Type DELETE to continue: ' answer </dev/tty
[[ "$answer" == DELETE ]] || { echo 'Cancelled.'; exit 0; }

keys="$(aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text)"
for key in $keys; do
  aws iam delete-access-key --user-name "$IAM_USER_NAME" --access-key-id "$key"
done
aws iam delete-user-policy --user-name "$IAM_USER_NAME" --policy-name IAM-PassRole-ECS
aws iam detach-user-policy --user-name "$IAM_USER_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam detach-user-policy --user-name "$IAM_USER_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
aws iam delete-user --user-name "$IAM_USER_NAME"
echo 'Part-2 IAM user and access keys deleted. GitHub and ECR were not changed.'
