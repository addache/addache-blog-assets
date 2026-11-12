#!/usr/bin/env bash
set +x
set +v
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./settings.local.sh
source ./save-settings.sh
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
mkdir -p .generated

export PATH="$HOME/.local/bin:$PATH"
command -v gh >/dev/null || { echo 'Run install-gh.sh first.' >&2; exit 1; }
gh auth status --hostname github.com
[[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$GITHUB_REPOSITORY" != *REPLACE_WITH* ]] || { echo 'Set GITHUB_REPOSITORY to owner/repository.' >&2; exit 1; }
git check-ref-format --branch "$WORK_BRANCH" >/dev/null
gh repo view "$GITHUB_REPOSITORY" --json nameWithOwner,isPrivate,viewerPermission --jq . > .generated/target-repository.json
jq -e '.isPrivate and (.viewerPermission=="ADMIN" or .viewerPermission=="MAINTAIN" or .viewerPermission=="WRITE")' .generated/target-repository.json >/dev/null || { echo 'Use a private repository with write access.' >&2; exit 1; }
[[ ! -e repository ]] || { echo 'repository/ already exists. Inspect the checkout and resume with git; do not reclone over it.' >&2; exit 1; }
for file in .github/workflows/deploy.yml app.py requirements.txt Dockerfile; do
  [[ -f "files/$file" ]] || { echo 'Run prepare-files.sh first.' >&2; exit 1; }
done

gh repo clone "$GITHUB_REPOSITORY" repository

for file in .github/workflows app.py requirements.txt Dockerfile; do
  [[ ! -e "repository/$file" ]] || { printf 'Existing path: %s. Use the GUI procedure for this repository.\n' "$file" >&2; exit 1; }
done
if git -C repository show-ref --verify --quiet "refs/remotes/origin/$WORK_BRANCH"; then
  echo 'Work branch already exists. Use another unused branch name.' >&2
  exit 1
fi

if git -C repository rev-parse --verify HEAD >/dev/null 2>&1; then
  git -C repository switch -c "$WORK_BRANCH"
else
  git -C repository switch --orphan "$WORK_BRANCH"
fi

mkdir -p repository/.github/workflows
cp files/.github/workflows/deploy.yml repository/.github/workflows/deploy.yml
cp files/app.py files/requirements.txt files/Dockerfile repository/

gh api user --jq '{login:.login,id:.id}' > .generated/github-identity.json
GITHUB_LOGIN="$(jq -r '.login' .generated/github-identity.json)"
GITHUB_USER_ID="$(jq -r '.id' .generated/github-identity.json)"
GIT_EMAIL="${GITHUB_USER_ID}+${GITHUB_LOGIN}@users.noreply.github.com"
save_settings GITHUB_LOGIN GITHUB_USER_ID GIT_EMAIL
git -C repository config user.name "$GITHUB_LOGIN"
git -C repository config user.email "$GIT_EMAIL"

git -C repository add -- .github/workflows/deploy.yml app.py requirements.txt Dockerfile
git -C repository diff --cached --stat
GIT_AUTHOR_NAME="$GITHUB_LOGIN" GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
  GIT_COMMITTER_NAME="$GITHUB_LOGIN" GIT_COMMITTER_EMAIL="$GIT_EMAIL" \
  git -C repository -c commit.gpgsign=false commit -m 'Add ECS image build sample'
FILES_COMMIT="$(git -C repository rev-parse HEAD)"
save_settings FILES_COMMIT

git -C repository push --set-upstream origin "$WORK_BRANCH"
PUSHED_COMMIT="$FILES_COMMIT"
save_settings PUSHED_COMMIT
printf 'Files: https://github.com/%s/tree/%s\n' "$GITHUB_REPOSITORY" "$WORK_BRANCH"
