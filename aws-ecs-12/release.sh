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
[[ "$IMAGE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a version tag such as v1.0.0.' >&2; exit 1; }
[[ "${PUSHED_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Publish the files first.' >&2; exit 1; }
gh repo view "$GITHUB_REPOSITORY" --json isPrivate --jq .isPrivate | grep -qx true
remote_url="$(git -C repository remote get-url origin)"
case "$remote_url" in "https://github.com/$GITHUB_REPOSITORY"|"https://github.com/$GITHUB_REPOSITORY.git"|"git@github.com:$GITHUB_REPOSITORY.git") ;; *) echo 'Checkout remote does not match settings.' >&2; exit 1;; esac
[[ "$(git -C repository rev-parse HEAD)" == "$PUSHED_COMMIT" ]] || { echo 'Checkout commit changed. Review before tagging.' >&2; exit 1; }
remote_commit="$(git -C repository ls-remote --exit-code origin "refs/heads/$WORK_BRANCH" | cut -f1)"
[[ "$remote_commit" == "$PUSHED_COMMIT" ]] || { echo 'Remote branch changed. Review before tagging.' >&2; exit 1; }
[[ -z "$(git -C repository status --porcelain)" ]] || { echo 'Checkout has uncommitted changes.' >&2; exit 1; }
gh secret list --repo "$GITHUB_REPOSITORY" --json name > .generated/secret-names.json
jq -e 'map(.name) | index("AWS_ACCESS_KEY_ID")!=null and index("AWS_SECRET_ACCESS_KEY")!=null' .generated/secret-names.json >/dev/null || { echo 'Register the two Actions Secrets manually first.' >&2; exit 1; }
git -C repository fetch origin --tags
if git -C repository show-ref --verify --quiet "refs/tags/$IMAGE_TAG"; then
  echo 'Tag already exists. Choose another unused IMAGE_TAG.' >&2
  exit 1
fi

git -C repository tag "$IMAGE_TAG" "$PUSHED_COMMIT"

git -C repository push origin "refs/tags/$IMAGE_TAG"

gh release create "$IMAGE_TAG" --repo "$GITHUB_REPOSITORY" --verify-tag \
  --title "$IMAGE_TAG" --generate-notes
