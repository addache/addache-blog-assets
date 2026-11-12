#!/usr/bin/env bash
# Fake gh + local bare Git repositories. No GitHub/AWS network calls.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
export GIT_CONFIG_GLOBAL="$test_root/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export HOME="$test_root/home"
mkdir -p "$HOME"
mkdir -p "$test_root/bin"
cat > "$test_root/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  'auth status') exit 0 ;;
  'repo view') printf '%s\n' '{"nameWithOwner":"fixture/private-repo","isPrivate":true,"viewerPermission":"WRITE"}' ;;
  'repo clone') git clone "$FIXTURE_REMOTE" "$4" ;;
  'api user') printf '%s\n' '{"login":"fixture","id":1234}' ;;
  *) echo 'Unexpected gh command' >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$test_root/bin/gh"
export PATH="$test_root/bin:$PATH"

for scenario in empty existing collision; do
  fixture="$test_root/$scenario"
  mkdir -p "$fixture/files/.github/workflows"
  cp "$repo_root/aws-ecs-12/publish-files.sh" "$repo_root/aws-ecs-12/save-settings.sh" "$fixture/"
  cp "$repo_root/aws-ecs-02/app.py" "$repo_root/aws-ecs-02/Dockerfile" "$repo_root/aws-ecs-02/requirements.txt" "$fixture/files/"
  cp "$repo_root/aws-ecs-02/.github/workflows/deploy.yml" "$fixture/files/.github/workflows/"
  cat > "$fixture/settings.local.sh" <<'SETTINGS'
AWS_REGION='ap-northeast-1'
GITHUB_REPOSITORY='fixture/private-repo'
WORK_BRANCH='ecs-cli-sample'
SETTINGS
  export FIXTURE_REMOTE="$fixture/remote.git"
  git init --bare --initial-branch=main "$FIXTURE_REMOTE" >/dev/null
  if [[ "$scenario" != empty ]]; then
    git clone "$FIXTURE_REMOTE" "$fixture/seed" >/dev/null
    git -C "$fixture/seed" config user.name fixture
    git -C "$fixture/seed" config user.email fixture@users.noreply.github.com
    printf 'Keep this existing file.\n' > "$fixture/seed/README.md"
    if [[ "$scenario" == collision ]]; then printf 'Keep existing application.\n' > "$fixture/seed/app.py"; fi
    git -C "$fixture/seed" add --all
    git -C "$fixture/seed" commit -m 'Existing fixture' >/dev/null
    git -C "$fixture/seed" push origin main >/dev/null
  fi
  if [[ "$scenario" == collision ]]; then
    if bash "$fixture/publish-files.sh"; then echo 'Collision was not blocked' >&2; exit 1; fi
    if git --git-dir="$FIXTURE_REMOTE" show-ref --verify --quiet refs/heads/ecs-cli-sample; then
      echo 'Unexpected branch created after conflict' >&2; exit 1
    fi
    test "$(git --git-dir="$FIXTURE_REMOTE" show main:app.py)" = 'Keep existing application.'
  else
    GIT_AUTHOR_EMAIL='outside@example.invalid' GIT_COMMITTER_EMAIL='outside@example.invalid' \
      bash "$fixture/publish-files.sh"
    git --git-dir="$FIXTURE_REMOTE" show ecs-cli-sample:app.py > "$fixture/uploaded.py"
    cmp "$fixture/files/app.py" "$fixture/uploaded.py"
    test "$(git --git-dir="$FIXTURE_REMOTE" log -1 --format=%ae ecs-cli-sample)" = '1234+fixture@users.noreply.github.com'
    test "$(git --git-dir="$FIXTURE_REMOTE" log -1 --format=%an ecs-cli-sample)" = fixture
    source "$fixture/settings.local.sh"
    test "$PUSHED_COMMIT" = "$(git --git-dir="$FIXTURE_REMOTE" rev-parse ecs-cli-sample)"
    test "$FILES_COMMIT" = "$PUSHED_COMMIT"
    expected=4
    if [[ "$scenario" == existing ]]; then
      expected=5
      test "$(git --git-dir="$FIXTURE_REMOTE" show ecs-cli-sample:README.md)" = 'Keep this existing file.'
    fi
    test "$(git --git-dir="$FIXTURE_REMOTE" ls-tree -r --name-only ecs-cli-sample | wc -l)" = "$expected"
    test -z "$(git --git-dir="$FIXTURE_REMOTE" tag --list)"
  fi
  printf 'PASS: publishing fixture %s\n' "$scenario"
done
