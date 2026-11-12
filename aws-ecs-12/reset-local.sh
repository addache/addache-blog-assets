#!/usr/bin/env bash
# Reset local part-2 checkout and saved commit IDs without deleting user files.
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ -f settings.local.sh && ! -L settings.local.sh ]] || { echo 'Expected a regular settings.local.sh.' >&2; exit 1; }
backup_dir="$(mktemp -d ./local-backup.XXXXXX)"
cp -p -- settings.local.sh "$backup_dir/settings.local.sh"
if [[ -e repository || -L repository ]]; then
  mv -- repository "$backup_dir/repository"
fi
tmp="$(mktemp ./settings.local.sh.tmp.XXXXXX)"
trap 'rm -f -- "$tmp"' EXIT
sed -E '/^[[:space:]]*(export[[:space:]]+)?(FILES_COMMIT|PUSHED_COMMIT)[[:space:]]*=/d' settings.local.sh > "$tmp"
chmod 600 "$tmp"
mv -- "$tmp" settings.local.sh
printf 'Local checkout and settings backup: %s\n' "$backup_dir"
echo 'FILES_COMMIT and PUSHED_COMMIT were removed from saved settings.'
echo 'In your current shell, run: unset FILES_COMMIT PUSHED_COMMIT'
