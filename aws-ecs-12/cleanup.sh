#!/usr/bin/env bash
# Delete part-2 Secrets, the dedicated IAM user and keys, and selected ECR tags.
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
export PATH="$HOME/.local/bin:$PATH"
gh auth status --hostname github.com
gh repo view "$GITHUB_REPOSITORY" --json isPrivate --jq .isPrivate | grep -qx true
[[ "$IMAGE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Check IMAGE_TAG.' >&2; exit 1; }
mkdir -p .generated
gh run list --repo "$GITHUB_REPOSITORY" --limit 100 --json status > .generated/cleanup-runs.json
jq -e 'all(.[]; .status=="completed")' .generated/cleanup-runs.json >/dev/null || { echo 'Wait for GitHub Actions to finish or cancel active runs first.' >&2; exit 1; }
gh secret list --repo "$GITHUB_REPOSITORY" --json name > .generated/cleanup-secret-names.json
aws ecr describe-images --registry-id "$AWS_ACCOUNT_ID" --repository-name "$ECR_REPOSITORY" --output json > .generated/cleanup-images.json
jq --arg tag "$IMAGE_TAG" '
  ([.imageDetails[] | select((.imageTags // []) | index($tag))] | .[0].imageDigest) as $digest |
  if $digest==null then [] else
    [{imageTag:$tag}] +
    (if any(.imageDetails[]; .imageDigest==$digest and ((.imageTags // []) | index("latest"))!=null)
     then [{imageTag:"latest"}] else [] end)
  end' .generated/cleanup-images.json > .generated/cleanup-image-ids.json
printf 'Account: %s\nIAM user: %s\nGitHub: %s\nECR: %s\n' "$AWS_ACCOUNT_ID" "$IAM_USER_NAME" "$GITHUB_REPOSITORY" "$ECR_REPOSITORY"
echo 'The two Actions Secrets, all access keys of this IAM user, this IAM user, and the selected ECR tags will be deleted.'
echo 'Shared part-1 resources, the GitHub repository, local settings, and GitHub login will remain.'
jq . .generated/cleanup-image-ids.json
read -r -p 'Type DELETE to continue: ' answer </dev/tty
[[ "$answer" == DELETE ]] || { echo 'Cancelled.'; exit 0; }
for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  if jq -e --arg name "$name" 'any(.[]; .name==$name)' .generated/cleanup-secret-names.json >/dev/null; then
    gh secret delete "$name" --repo "$GITHUB_REPOSITORY"
  fi
done

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

if jq -e 'length>0' .generated/cleanup-image-ids.json >/dev/null; then
  aws ecr batch-delete-image --registry-id "$AWS_ACCOUNT_ID" --repository-name "$ECR_REPOSITORY" \
    --image-ids file://.generated/cleanup-image-ids.json --output json > .generated/cleanup-images-result.json
  jq . .generated/cleanup-images-result.json
  jq -e '.failures | length==0' .generated/cleanup-images-result.json >/dev/null || { echo 'Some ECR tags could not be deleted. Review failures.' >&2; exit 1; }
fi
echo 'Part-2 cleanup completed. The repository, shared resources, local settings, and GitHub login remain.'
