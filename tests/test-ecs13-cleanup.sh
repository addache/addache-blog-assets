#!/usr/bin/env bash
# Exercise cleanup with a fake AWS CLI; never contact AWS.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
export HOME="$root/home"
export MOCK_LOG="$root/calls"
mkdir -p "$HOME/aws-ecs-11" "$HOME/aws-ecs-12" "$HOME/aws-ecs-13/.generated" "$root/bin"
export PATH="$root/bin:$PATH"
cat > "$HOME/aws-ecs-11/settings.local.sh" <<'EOF'
AWS_ACCOUNT_ID=123456789012
AWS_REGION=ap-northeast-1
S3_BUCKET=sample-bucket
API_URL=http://new-alb/api
EOF
: > "$HOME/aws-ecs-12/settings.local.sh"
cat > "$HOME/aws-ecs-13/settings.local.sh" <<'EOF'
CLUSTER_NAME=sample-cluster
SERVICE_NAME=sample-service
TASK_DEFINITION_ARN=arn:aws:ecs:ap-northeast-1:123456789012:task-definition/sample:1
ALB_ARN=arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/sample/one
TARGET_GROUP_ARN=arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/sample/one
ALB_SG_ID=sg-alb
ECS_SG_ID=sg-ecs
LOG_GROUP=/ecs/sample
PREVIOUS_API_URL=http://old-api/api
EOF
cp "$repo_root/aws-ecs-13/save-settings.sh" "$HOME/aws-ecs-13/"
echo 'const API_URL = "http://old-api/api";' > "$HOME/aws-ecs-13/.generated/app.original.js"
cat > "$root/bin/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$1 $2" in
 'sts get-caller-identity') echo 123456789012;;
 'ecs describe-services') echo '{"services":[{"status":"ACTIVE"}],"failures":[]}';;
 'ecs list-services') echo '{"serviceArns":["arn:aws:ecs:ap-northeast-1:123456789012:service/sample-cluster/sample-service"]}';;
 'ecs list-tasks') echo '{"taskArns":[]}';;
 's3api put-object')
   while [[ $# -gt 0 ]]; do
     if [[ "$1" == --body ]]; then cp "$2" "$HOME/restored-app.js"; break; fi
     shift
   done
   echo '{}';;
 *) echo '{}';;
esac
EOF
chmod +x "$root/bin/aws"
# Only substitute the interactive answer in the isolated test copy.
sed "s/^read -r -p .* answer <\/dev\/tty$/answer=DELETE/" "$repo_root/aws-ecs-13/cleanup.sh" > "$HOME/aws-ecs-13/cleanup.sh"
bash "$HOME/aws-ecs-13/cleanup.sh"
source "$HOME/aws-ecs-11/settings.local.sh"
test "$API_URL" = http://old-api/api
grep -q 'old-api' "$HOME/restored-app.js"
test ! -d "$HOME/aws-ecs-13/.generated"
! grep -q '^ALB_ARN=' "$HOME/aws-ecs-13/settings.local.sh"
grep -q '^CLUSTER_NAME=sample-cluster' "$HOME/aws-ecs-13/settings.local.sh"
python3 - "$MOCK_LOG" <<'PY'
import sys
s=open(sys.argv[1]).read()
need=['ecs update-service','ecs wait services-stable','ecs delete-service','ecs wait services-inactive','elbv2 delete-load-balancer','elbv2 wait load-balancers-deleted','elbv2 delete-target-group','ecs deregister-task-definition','ecs delete-cluster','ec2 delete-security-group --group-id sg-ecs','ec2 delete-security-group --group-id sg-alb','logs delete-log-group','s3api put-object']
positions=[s.index(x) for x in need]
assert positions==sorted(positions)
assert 'dynamodb ' not in s and 'iam ' not in s and 'ecr ' not in s
print('PASS: cleanup dependency order, shared resource isolation, original app and API restoration, generated-state archive')
PY
