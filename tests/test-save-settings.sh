#!/usr/bin/env bash
# Local fixture tests only. No AWS credentials, API calls, or resource changes.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

for part in 11 12 13; do
  fixture="$test_root/part $part"
  mkdir -p "$fixture"
  cp "$repo_root/aws-ecs-$part/save-settings.sh" "$fixture/save-settings.sh"
  cat > "$fixture/settings.local.sh" <<'SETTINGS'
# Preserve this comment and unrelated settings.
AWS_REGION='ap-northeast-1'
API_URL='old-first'
export API_URL='old-second'
SETTINGS
  source "$fixture/save-settings.sh"
  EXECUTION_ROLE_ARN='arn:aws:iam::123456789012:role/sample'
  S3_BUCKET='sample-web-123456789012-ap-northeast-1-an'
  API_URL='http://example.invalid/api?x=one&y=two'
  export WEBSITE_URL='http://example.invalid/'
  TEST_VALUE=$'space "double" \'single\' $HOME $(touch injected) `touch injected` \\ backslash\nnext line'
  SUBNET_IDS=('subnet-one' 'subnet-two' 'value with spaces' '$(touch injected)')
  expected_value="$TEST_VALUE"
  expected_api="$API_URL"
  save_settings EXECUTION_ROLE_ARN S3_BUCKET API_URL WEBSITE_URL TEST_VALUE SUBNET_IDS
  API_URL='http://example.invalid/updated'
  expected_api="$API_URL"
  save_settings API_URL
  save_settings API_URL
  for name in EXECUTION_ROLE_ARN S3_BUCKET API_URL WEBSITE_URL TEST_VALUE SUBNET_IDS; do
    test "$(grep -c "^${name}=" "$fixture/settings.local.sh")" = 1
  done
  grep -Fq '# Preserve this comment and unrelated settings.' "$fixture/settings.local.sh"
  grep -Fq "AWS_REGION='ap-northeast-1'" "$fixture/settings.local.sh"
  unset EXECUTION_ROLE_ARN S3_BUCKET API_URL WEBSITE_URL TEST_VALUE SUBNET_IDS
  cd "$fixture"
  source ./settings.local.sh
  test "$TEST_VALUE" = "$expected_value"
  test "$API_URL" = "$expected_api"
  test "$S3_BUCKET" = 'sample-web-123456789012-ap-northeast-1-an'
  test "$EXECUTION_ROLE_ARN" = 'arn:aws:iam::123456789012:role/sample'
  test "$WEBSITE_URL" = 'http://example.invalid/'
  test "${#SUBNET_IDS[@]}" = 4
  test "${SUBNET_IDS[2]}" = 'value with spaces'
  test "${SUBNET_IDS[3]}" = '$(touch injected)'
  test ! -e injected
  bash -n ./settings.local.sh
  bash -c 'set -euo pipefail; source "$1"; test "${#SUBNET_IDS[@]}" = 4; test "$S3_BUCKET" = sample-web-123456789012-ap-northeast-1-an; test ! -e injected' _ "$fixture/settings.local.sh"
  cp ./settings.local.sh ./before-failure.sh
  unset UNSET_SETTING || true
  if save_settings UNSET_SETTING; then echo 'Unset variable was accepted' >&2; exit 1; fi
  EMPTY_SETTING=''
  if save_settings EMPTY_SETTING; then echo 'Empty variable was accepted' >&2; exit 1; fi
  MISSING_SETTING='None'
  if save_settings MISSING_SETTING; then echo 'Missing AWS result was accepted' >&2; exit 1; fi
  EMPTY_ARRAY=()
  if save_settings EMPTY_ARRAY; then echo 'Empty array was accepted' >&2; exit 1; fi
  if save_settings 'INVALID;touch injected'; then echo 'Invalid name was accepted' >&2; exit 1; fi
  cmp ./settings.local.sh ./before-failure.sh
  test "$(stat -c %a ./settings.local.sh)" = 600
  test -z "$(find . -maxdepth 1 -name 'settings.local.sh.tmp.*' -print)"
  cd "$repo_root"
  printf 'PASS: part %s scalar/array restore, quoting, duplicate update, failure protection, permissions\n' "$part"
done
