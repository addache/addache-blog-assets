# AWS CloudShell (Bash). Copy to settings.local.sh.
# Preparation commands set the account ID automatically.
AWS_ACCOUNT_ID='REPLACE_WITH_12_DIGIT_AWS_ACCOUNT_ID'
AWS_REGION='ap-northeast-1'

# Existing resources from part 1 and the image pushed in part 2.
EXECUTION_ROLE_NAME='ecs-task-execution-role'
TASK_ROLE_NAME='ecs-task-role'
DYNAMODB_TABLE='ecs-sample-messages'
ECR_REPOSITORY='ecs-sample-api'
IMAGE_TAG='v1.0.0'
S3_BUCKET_PREFIX='ecs-sample-web'

# New resources. Use unused names if the GUI environment still exists.
ALB_SG_NAME='ALB-SEG'
ECS_SG_NAME='ECS-SEG'
CLUSTER_NAME='ecs-sample-cluster'
TASK_FAMILY='ecs-sample'
SERVICE_NAME='ecs-sample-service'
ALB_NAME='ecs-sample-alb'
TARGET_GROUP_NAME='ecs-sample-tg'
LOG_GROUP='/ecs/ecs-sample'
