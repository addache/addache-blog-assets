#!/usr/bin/env bash
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ ! -e files ]] || { echo 'files/ already exists. Review it instead of overwriting it.' >&2; exit 1; }
mkdir -p files/.github/workflows
BASE_URL='https://raw.githubusercontent.com/addache/addache-blog-assets/main/aws-ecs-02'
curl -fSLo files/.github/workflows/deploy.yml "$BASE_URL/.github/workflows/deploy.yml"
curl -fSLo files/app.py "$BASE_URL/app.py"
curl -fSLo files/requirements.txt "$BASE_URL/requirements.txt"
curl -fSLo files/Dockerfile "$BASE_URL/Dockerfile"
echo 'Four files downloaded to files/. Review them before publishing.'
