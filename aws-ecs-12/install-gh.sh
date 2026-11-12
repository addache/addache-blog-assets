#!/usr/bin/env bash
# Install the official GitHub CLI release into the CloudShell home directory.
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export PATH="$HOME/.local/bin:$PATH"
if command -v gh >/dev/null; then gh --version; exit 0; fi
case "$(uname -m)" in x86_64) arch=amd64;; aarch64) arch=arm64;; *) echo 'Unsupported CPU architecture.' >&2; exit 1;; esac
mkdir -p .generated/gh-install "$HOME/.local/bin"
curl -fSL https://api.github.com/repos/cli/cli/releases/latest -o .generated/gh-install/release.json
version="$(jq -r '.tag_name' .generated/gh-install/release.json)"
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Could not identify GitHub CLI release.' >&2; exit 1; }
number="${version#v}"
archive="gh_${number}_linux_${arch}.tar.gz"
checksums="gh_${number}_checksums.txt"
base="https://github.com/cli/cli/releases/download/$version"
curl -fSL "$base/$archive" -o ".generated/gh-install/$archive"
curl -fSL "$base/$checksums" -o ".generated/gh-install/$checksums"
(
  cd .generated/gh-install
  checksum_line="$(grep -F "  $archive" "$checksums")"
  [[ "$(printf '%s\n' "$checksum_line" | wc -l)" == 1 && -n "$checksum_line" ]]
  printf '%s\n' "$checksum_line" | sha256sum -c -
  tar -xzf "$archive"
)
install -m 755 ".generated/gh-install/gh_${number}_linux_${arch}/bin/gh" "$HOME/.local/bin/gh"
"$HOME/.local/bin/gh" --version
