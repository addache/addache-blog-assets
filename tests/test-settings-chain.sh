#!/usr/bin/env bash
# Local settings fixtures only. No AWS or GitHub network calls.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
export HOME="$test_root/home"
mkdir -p "$HOME/aws-ecs-11" "$HOME/aws-ecs-12" "$HOME/aws-ecs-13"
cat > "$HOME/aws-ecs-11/settings.local.sh" <<'PART1'
AWS_ACCOUNT_ID='123456789012'
AWS_REGION='ap-northeast-1'
EXECUTION_ROLE_NAME='custom-execution'
TASK_ROLE_NAME='custom-task'
EXECUTION_ROLE_ARN='arn:aws:iam::123456789012:role/custom-execution'
TASK_ROLE_ARN='arn:aws:iam::123456789012:role/custom-task'
DYNAMODB_TABLE='custom-messages'
ECR_REPOSITORY='custom-api'
ECR_URI='123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/custom-api'
S3_BUCKET_PREFIX='custom-web'
S3_BUCKET='custom-web-123456789012-ap-northeast-1-an'
WEBSITE_URL='http://example.invalid/'
API_URL='http://api.example.invalid/api'
PART1
cp "$repo_root/aws-ecs-12/settings.example.sh" "$HOME/aws-ecs-12/settings.local.sh"
cp "$repo_root/aws-ecs-13/settings.example.sh" "$HOME/aws-ecs-13/settings.local.sh"
cp "$repo_root/aws-ecs-12/save-settings.sh" "$HOME/aws-ecs-12/"
cp "$repo_root/aws-ecs-13/save-settings.sh" "$HOME/aws-ecs-13/"
sed -i "s/IMAGE_TAG='v1.0.0'/IMAGE_TAG='v9.8.7'/" "$HOME/aws-ecs-12/settings.local.sh"

source ~/aws-ecs-11/settings.local.sh
source ~/aws-ecs-12/settings.local.sh
source ~/aws-ecs-12/save-settings.sh
test "$AWS_ACCOUNT_ID" = 123456789012
test "$EXECUTION_ROLE_NAME" = custom-execution
IAM_USER_ARN='arn:aws:iam::123456789012:user/ecs-github-user'
save_settings IAM_USER_ARN
grep -q '^IAM_USER_ARN=' "$HOME/aws-ecs-12/settings.local.sh"
! grep -q '^IAM_USER_ARN=' "$HOME/aws-ecs-11/settings.local.sh"

source ~/aws-ecs-11/settings.local.sh
source ~/aws-ecs-12/settings.local.sh
source ~/aws-ecs-13/settings.local.sh
source ~/aws-ecs-13/save-settings.sh
test "$IMAGE_TAG" = v9.8.7
test "$TASK_ROLE_NAME" = custom-task
test "$DYNAMODB_TABLE" = custom-messages
test "$ECR_REPOSITORY" = custom-api
test "$S3_BUCKET" = custom-web-123456789012-ap-northeast-1-an
ALB_ARN='arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/sample/fixture'
SUBNET_IDS=('subnet-first' 'subnet-second')
save_settings ALB_ARN SUBNET_IDS
API_URL='http://new-alb.example.invalid/api'
save_settings_to ~/aws-ecs-11/settings.local.sh API_URL
save_settings_to ~/aws-ecs-11/settings.local.sh API_URL
TARGET_GROUP_ARN='arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/sample/fixture'
save_settings TARGET_GROUP_ARN

test "$(grep -c '^API_URL=' "$HOME/aws-ecs-11/settings.local.sh")" = 1
! grep -q '^API_URL=' "$HOME/aws-ecs-12/settings.local.sh"
! grep -q '^API_URL=' "$HOME/aws-ecs-13/settings.local.sh"
grep -q '^ALB_ARN=' "$HOME/aws-ecs-13/settings.local.sh"
grep -q '^TARGET_GROUP_ARN=' "$HOME/aws-ecs-13/settings.local.sh"
! grep -q '^ALB_ARN=' "$HOME/aws-ecs-11/settings.local.sh"
! grep -q '^ALB_ARN=' "$HOME/aws-ecs-12/settings.local.sh"
bash -c '
  set -euo pipefail
  source ~/aws-ecs-11/settings.local.sh
  source ~/aws-ecs-12/settings.local.sh
  source ~/aws-ecs-13/settings.local.sh
  test "$API_URL" = http://new-alb.example.invalid/api
  test "$IMAGE_TAG" = v9.8.7
  test "$ECR_REPOSITORY" = custom-api
  test "${#SUBNET_IDS[@]}" = 2
  test "${SUBNET_IDS[1]}" = subnet-second
  test -n "$IAM_USER_ARN"
  test -n "$ALB_ARN"
'
printf 'PASS: inherited settings, per-part save ownership, shared API update, fresh-shell restore\n'
