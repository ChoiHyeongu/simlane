#!/usr/bin/env bash
# Assert a release tag matches VERSION and the newest CHANGELOG section: check-release.sh vX.Y.Z [REPO_ROOT]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
tag=${1:?usage: check-release.sh vX.Y.Z [REPO_ROOT]}
root=${2:-$(cd "$here/.." && pwd -P)}
fail() { echo "check-release: $*" >&2; exit 1; }

printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || fail "not a release tag: $tag"
v=${tag#v}
[ -f "$root/VERSION" ] || fail "VERSION file missing in $root"
file_v=$(tr -d '[:space:]' < "$root/VERSION")
[ "$file_v" = "$v" ] || fail "tag $tag but VERSION is $file_v"
top=$(awk '/^## / && $2 != "Unreleased" { print $2; exit }' "$root/CHANGELOG.md")
[ "$top" = "$v" ] || fail "tag $tag but the newest CHANGELOG section is ${top:-missing}"
"$here/changelog-section.sh" "$v" "$root/CHANGELOG.md" >/dev/null || fail "CHANGELOG section for $v is missing or empty"
echo "check-release: $tag ok"
