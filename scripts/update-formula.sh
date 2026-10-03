#!/usr/bin/env bash
# Point the Homebrew formula at a release: update-formula.sh FORMULA_RB X.Y.Z SHA256 → prints updated|unchanged
set -euo pipefail
f=${1:?usage: update-formula.sh FORMULA_RB X.Y.Z SHA256}
v=${2:?usage: update-formula.sh FORMULA_RB X.Y.Z SHA256}
sha=${3:?usage: update-formula.sh FORMULA_RB X.Y.Z SHA256}
fail() { echo "update-formula: $*" >&2; exit 1; }

printf '%s\n' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "bad version: $v"
printf '%s\n' "$sha" | grep -Eq '^[0-9a-f]{64}$' || fail "bad sha256: $sha"
if [ "$(grep -c '^  url "' "$f")" -ne 1 ] || [ "$(grep -c '^  sha256 "' "$f")" -ne 1 ]; then
  fail "expected exactly one top-level url and one sha256 line in $f"
fi

url="https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v$v.tar.gz"
tmp=$(mktemp)
sed -e "s|^  url \".*\"\$|  url \"$url\"|" -e "s|^  sha256 \".*\"\$|  sha256 \"$sha\"|" "$f" > "$tmp"
if cmp -s "$tmp" "$f"; then
  rm -f "$tmp"; echo unchanged
else
  cat "$tmp" > "$f"; rm -f "$tmp"; echo updated
fi
