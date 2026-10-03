#!/usr/bin/env bash
# Print one CHANGELOG section body: changelog-section.sh X.Y.Z|Unreleased [CHANGELOG]
# Heading lines look like "## 0.2.0 — 2026-10-04" or "## Unreleased". Exit 1 if the section is missing or empty.
set -euo pipefail
name=${1:?usage: changelog-section.sh X.Y.Z|Unreleased [CHANGELOG]}
f=${2:-$(cd "$(dirname "$0")/.." && pwd -P)/CHANGELOG.md}
rc=0
awk -v name="$name" '
  /^## / { if (found) exit; if ($2 == name) { found = 1; next } }
  found { lines[++n] = $0 }
  END {
    if (!found) exit 2
    s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
    e = n; while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--
    if (s > e) exit 3
    for (i = s; i <= e; i++) print lines[i]
  }
' "$f" || rc=$?
case $rc in
  0) ;;
  2) echo "changelog-section: no '## $name' section in $f" >&2; exit 1 ;;
  3) echo "changelog-section: '## $name' section is empty in $f" >&2; exit 1 ;;
  *) exit 1 ;;
esac
