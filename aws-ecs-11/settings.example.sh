# AWS CloudShell (Bash). Copy to settings.local.sh and edit that copy.
# The preparation commands fill AWS_ACCOUNT_ID using STS and sed.
AWS_ACCOUNT_ID='REPLACE_WITH_12_DIGIT_AWS_ACCOUNT_ID'
AWS_REGION='ap-northeast-1'

# Use unused names. Existing resources are not overwritten by this sample.
EXECUTION_ROLE_NAME='ecs-task-execution-role'
TASK_ROLE_NAME='ecs-task-role'
DYNAMODB_TABLE='ecs-sample-messages'
ECR_REPOSITORY='ecs-sample-api'
S3_BUCKET_PREFIX='ecs-sample-web'

# Part 1 only displays the website. Replace with the actual API URL in part 3.
API_URL='http://api.example.invalid/api'
