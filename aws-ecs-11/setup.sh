#!/usr/bin/env bash
# AWS CloudShell (Bash): bash setup.sh
# Draft sample: creates AWS resources and publicly serves two sample web files.
set +x
set +v
set -euo pipefail
umask 077

# STEP: prepare
ASSET_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ASSET_DIR"
[[ -f settings.local.sh ]] || { echo 'Copy settings.example.sh to settings.local.sh and edit it first.' >&2; exit 1; }
source ./settings.local.sh
for tool in aws jq grep sed curl; do
  command -v "$tool" >/dev/null || { printf 'Required command missing: %s\n' "$tool" >&2; exit 1; }
done
for name in AWS_ACCOUNT_ID AWS_REGION EXECUTION_ROLE_NAME TASK_ROLE_NAME DYNAMODB_TABLE ECR_REPOSITORY S3_BUCKET_PREFIX API_URL; do
  value="${!name:-}"
  [[ -n "$value" && "$value" != *REPLACE_WITH* ]] || { printf 'Set %s in settings.local.sh first.\n' "$name" >&2; exit 1; }
done
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo 'AWS_ACCOUNT_ID must contain 12 digits.' >&2; exit 1; }
[[ "$AWS_REGION" == ap-northeast-1 ]] || { echo 'This draft targets ap-northeast-1 (Tokyo).' >&2; exit 1; }
[[ "$EXECUTION_ROLE_NAME" =~ ^[a-zA-Z0-9_-]{1,64}$ && "$TASK_ROLE_NAME" =~ ^[a-zA-Z0-9_-]{1,64}$ && "$EXECUTION_ROLE_NAME" != "$TASK_ROLE_NAME" ]] || { echo 'Use two different IAM role names.' >&2; exit 1; }
[[ "$DYNAMODB_TABLE" =~ ^[a-zA-Z0-9_.-]{3,255}$ ]] || { echo 'Invalid DynamoDB table name.' >&2; exit 1; }
[[ "$ECR_REPOSITORY" =~ ^[a-z][a-z0-9-]{1,100}$ ]] || { echo 'Use a simple lowercase ECR repository name.' >&2; exit 1; }
[[ "$S3_BUCKET_PREFIX" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || { echo 'Use a lowercase S3 prefix without dots.' >&2; exit 1; }
[[ "$API_URL" =~ ^https?://[a-zA-Z0-9.:/_-]+$ ]] || { echo 'Use a simple http(s) API URL without query parameters.' >&2; exit 1; }
export AWS_DEFAULT_REGION="$AWS_REGION" AWS_REGION
export AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
CALLER_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
[[ "$CALLER_ACCOUNT" == "$AWS_ACCOUNT_ID" ]] || { echo 'Signed-in AWS account does not match settings.local.sh.' >&2; exit 1; }
S3_BUCKET="${S3_BUCKET_PREFIX}-${AWS_ACCOUNT_ID}-${AWS_REGION}-an"
[[ ${#S3_BUCKET} -le 63 ]] || { echo 'S3 bucket name exceeds 63 characters. Shorten S3_BUCKET_PREFIX.' >&2; exit 1; }
mkdir -p .generated
printf 'Account=%s\nRegion=%s\nS3 bucket=%s\n' "$AWS_ACCOUNT_ID" "$AWS_REGION" "$S3_BUCKET"
aws sts get-caller-identity --output table
# Fail closed: permission/network errors must not be mistaken for a missing resource.
require_absent() {
  local label="$1" missing_code="$2"
  shift 2
  if "$@" > .generated/existing-resource.json 2> .generated/check-error.txt; then
    printf '%s already exists. Use unused names; no existing resource will be changed.\n' "$label" >&2
    exit 1
  elif ! grep -Eq "$missing_code" .generated/check-error.txt; then
    cat .generated/check-error.txt >&2
    exit 1
  fi
}

# STEP: preflight
require_absent 'Execution role' '\(NoSuchEntity\)' aws iam get-role --role-name "$EXECUTION_ROLE_NAME"
require_absent 'Task role' '\(NoSuchEntity\)' aws iam get-role --role-name "$TASK_ROLE_NAME"
require_absent 'DynamoDB table' '\(ResourceNotFoundException\)' aws dynamodb describe-table --table-name "$DYNAMODB_TABLE"
require_absent 'ECR repository' '\(RepositoryNotFoundException\)' aws ecr describe-repositories --repository-names "$ECR_REPOSITORY"
require_absent 'S3 bucket' '\(404\)|\(NoSuchBucket\)|\(NotFound\)' aws s3api head-bucket --bucket "$S3_BUCKET" --expected-bucket-owner "$AWS_ACCOUNT_ID"
# Check CLI support before creating anything. Older CLIs must be updated first.
aws s3api create-bucket --generate-cli-skeleton input > .generated/create-bucket-skeleton.json
jq -e 'has("BucketNamespace")' .generated/create-bucket-skeleton.json >/dev/null || { echo 'Update AWS CLI v2: account-regional namespace is not supported by this CLI.' >&2; exit 1; }

# STEP: iam
jq -n \
  '{
    Version: "2012-10-17",
    Statement: [{
      Effect: "Allow",
      Principal: {Service: "ecs-tasks.amazonaws.com"},
      Action: "sts:AssumeRole"
    }]
  }' > .generated/ecs-trust-policy.json
aws iam create-role --role-name "$EXECUTION_ROLE_NAME" \
  --assume-role-policy-document file://.generated/ecs-trust-policy.json \
  --query 'Role.{Name:RoleName,Arn:Arn}' --output table
aws iam attach-role-policy --role-name "$EXECUTION_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam create-role --role-name "$TASK_ROLE_NAME" \
  --assume-role-policy-document file://.generated/ecs-trust-policy.json \
  --query 'Role.{Name:RoleName,Arn:Arn}' --output table
aws iam attach-role-policy --role-name "$TASK_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess_v2
EXECUTION_ROLE_ARN="$(aws iam get-role --role-name "$EXECUTION_ROLE_NAME" --query Role.Arn --output text)"
TASK_ROLE_ARN="$(aws iam get-role --role-name "$TASK_ROLE_NAME" --query Role.Arn --output text)"
printf 'EXECUTION_ROLE_ARN=%s\nTASK_ROLE_ARN=%s\n' "$EXECUTION_ROLE_ARN" "$TASK_ROLE_ARN"
aws iam list-attached-role-policies --role-name "$EXECUTION_ROLE_NAME" --output table
aws iam list-attached-role-policies --role-name "$TASK_ROLE_NAME" --output table

# STEP: dynamodb
aws dynamodb create-table --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --query 'TableDescription.{Name:TableName,Status:TableStatus}' --output table
aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE"
aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" \
  --query 'Table.{Name:TableName,Status:TableStatus,Keys:KeySchema,BillingMode:BillingModeSummary.BillingMode}' --output json

# STEP: ecr
aws ecr create-repository --repository-name "$ECR_REPOSITORY" \
  --query 'repository.{Name:repositoryName,Uri:repositoryUri}' --output table
ECR_URI="$(aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --query 'repositories[0].repositoryUri' --output text)"
printf 'ECR_URI=%s\n' "$ECR_URI"

# STEP: s3
aws s3api create-bucket --bucket "$S3_BUCKET" \
  --bucket-namespace account-regional \
  --create-bucket-configuration "LocationConstraint=$AWS_REGION"
aws s3api wait bucket-exists --bucket "$S3_BUCKET" --expected-bucket-owner "$AWS_ACCOUNT_ID"
aws s3api get-bucket-location --bucket "$S3_BUCKET" --expected-bucket-owner "$AWS_ACCOUNT_ID" --output json
# The upload list is explicit: settings and generated policies are never uploaded.
sed "s|__API_URL__|$API_URL|g" web/app.js > .generated/app.js
aws s3api put-object --bucket "$S3_BUCKET" --key index.html --body web/index.html \
  --content-type 'text/html; charset=utf-8' --expected-bucket-owner "$AWS_ACCOUNT_ID" --output json
aws s3api put-object --bucket "$S3_BUCKET" --key app.js --body .generated/app.js \
  --content-type 'application/javascript; charset=utf-8' --expected-bucket-owner "$AWS_ACCOUNT_ID" --output json

# STEP: website
aws s3api put-bucket-website --bucket "$S3_BUCKET" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"}}' \
  --expected-bucket-owner "$AWS_ACCOUNT_ID"
# Match article 01: disable all four bucket-level public access blocks.
aws s3api put-public-access-block --bucket "$S3_BUCKET" \
  --public-access-block-configuration 'BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false' \
  --expected-bucket-owner "$AWS_ACCOUNT_ID"
jq -n --arg bucket "$S3_BUCKET" \
  '{Version:"2012-10-17",Statement:[{Sid:"PublicRead",Effect:"Allow",Principal:"*",Action:"s3:GetObject",Resource:("arn:aws:s3:::"+$bucket+"/*")}]}' \
  > .generated/s3-website-policy.json
aws s3api put-bucket-policy --bucket "$S3_BUCKET" \
  --policy file://.generated/s3-website-policy.json --expected-bucket-owner "$AWS_ACCOUNT_ID"
aws s3api get-bucket-website --bucket "$S3_BUCKET" --expected-bucket-owner "$AWS_ACCOUNT_ID" --output json
aws s3api get-public-access-block --bucket "$S3_BUCKET" --expected-bucket-owner "$AWS_ACCOUNT_ID" --output json

# STEP: verify
# Tokyo's S3 website endpoint uses s3-website-REGION, not s3-website.REGION.
WEBSITE_URL="http://${S3_BUCKET}.s3-website-ap-northeast-1.amazonaws.com"
printf '%s\n' "$WEBSITE_URL" > .generated/website-url.txt
jq -n --arg account "$AWS_ACCOUNT_ID" --arg region "$AWS_REGION" \
  --arg executionRole "$EXECUTION_ROLE_ARN" --arg taskRole "$TASK_ROLE_ARN" \
  --arg table "$DYNAMODB_TABLE" --arg ecr "$ECR_URI" --arg bucket "$S3_BUCKET" --arg website "$WEBSITE_URL" \
  '{accountId:$account,region:$region,executionRoleArn:$executionRole,taskRoleArn:$taskRole,dynamodbTable:$table,ecrUri:$ecr,s3Bucket:$bucket,websiteUrl:$website}' \
  > .generated/resources.json
curl --fail --show-error --silent --retry 5 --retry-delay 3 \
  --connect-timeout 10 --max-time 30 "$WEBSITE_URL/" -o .generated/website-check.html
curl --fail --show-error --silent --retry 5 --retry-delay 3 \
  --connect-timeout 10 --max-time 30 "$WEBSITE_URL/app.js" -o .generated/app-check.js
printf '\nWebsite URL: %s\n' "$WEBSITE_URL"
echo 'Open the HTTP URL in your browser. Part 1 ends at displaying the page.'
echo 'The API button is expected to fail until the backend is created in later parts.'
echo 'Resource details: .generated/resources.json'
