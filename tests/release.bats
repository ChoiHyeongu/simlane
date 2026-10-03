#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; S="$SIMLANE_ROOT/scripts/release.sh"; O="$TD/origin.git"; R="$TD/r"
  git init -q --bare "$O"
  git clone -q "$O" "$R" 2>/dev/null
  ( cd "$R" && git symbolic-ref HEAD refs/heads/main && git config user.email t@t.local && git config user.name t \
    && echo 0.1.0 > VERSION \
    && printf '%s\n' '# Changelog' '' '## Unreleased' '' '- feat: something' '' '## 0.1.0 — 2026-10-01' '' '- first' > CHANGELOG.md \
    && git add -A && git commit -qm init && git push -q origin main )
  TODAY=$(date +%Y-%m-%d)
}
rel() {   # ANSWER ARGS… → run release.sh inside $R with ANSWER on stdin and a stub test command
  local ans=$1; shift
  ( cd "$R" && printf '%s\n' "$ans" | SIMLANE_RELEASE_TEST_CMD="${TESTCMD:-true}" "$S" "$@" )
}
clean() { [ -z "$(git -C "$R" status --porcelain)" ]; }

@test "release: rejects a malformed version" {
  run rel y 0.2; [ "$status" -eq 1 ]; assert_contains "$output" "usage"
}

@test "release: refuses a dirty tree, a non-increasing version, an existing tag and a stale main" {
  touch "$R/junk"; run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "not clean"; rm "$R/junk"
  run rel y 0.1.0; [ "$status" -eq 1 ]; assert_contains "$output" "not greater"
  git -C "$R" tag v0.2.0; run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "already exists"
  git -C "$R" tag -d v0.2.0 >/dev/null
  git clone -q "$O" "$TD/other"
  ( cd "$TD/other" && git config user.email t@t.local && git config user.name t && echo x > x && git add x \
    && git commit -qm other && git push -q origin main )
  run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "not in sync"
  [ "$(cat "$R/VERSION")" = "0.1.0" ]
}

@test "release: an Unreleased section with only blank lines blocks the release" {
  ( cd "$R" && printf '%s\n' '# Changelog' '' '## Unreleased' '' '' '## 0.1.0 — 2026-10-01' '' '- first' > CHANGELOG.md \
    && git commit -qam empty && git push -q origin main )
  run rel y 0.2.0; [ "$status" -eq 1 ]; assert_contains "$output" "Unreleased"; clean
}

@test "release: failing tests stop before any file changes" {
  TESTCMD=false run rel y 0.2.0
  [ "$status" -eq 1 ]; assert_contains "$output" "tests failed"; clean; [ "$(cat "$R/VERSION")" = "0.1.0" ]
}

@test "release: declining the push keeps the local commit and tag and prints how to undo" {
  run rel n 0.2.0
  [ "$status" -eq 0 ]; assert_contains "$output" "git tag -d v0.2.0 && git reset --hard HEAD~1"
  [ "$(cat "$R/VERSION")" = "0.2.0" ]
  [ "$(sed -n 3p "$R/CHANGELOG.md")" = "## Unreleased" ]
  [ "$(sed -n 5p "$R/CHANGELOG.md")" = "## 0.2.0 — $TODAY" ]
  [ "$(sed -n 7p "$R/CHANGELOG.md")" = "- feat: something" ]
  [ "$(git -C "$R" log -1 --format=%s)" = "chore(release): 0.2.0" ]
  [ "$(git -C "$R" cat-file -t v0.2.0)" = "tag" ]
  assert_fails git -C "$O" rev-parse -q --verify refs/tags/v0.2.0
}

@test "release: accepting pushes main and the annotated tag together; works from a subdirectory" {
  mkdir -p "$R/sub" && touch "$R/sub/.keep" && ( cd "$R" && git add -A && git commit -qm sub && git push -q origin main )
  run bash -c "cd '$R/sub' && printf 'y\n' | SIMLANE_RELEASE_TEST_CMD=true '$S' 0.2.0"
  [ "$status" -eq 0 ]; assert_contains "$output" "pushed v0.2.0"
  [ "$(git -C "$O" rev-parse main)" = "$(git -C "$R" rev-parse HEAD)" ]
  [ "$(git -C "$O" rev-parse 'v0.2.0^{commit}')" = "$(git -C "$R" rev-parse HEAD)" ]
  [ "$(git -C "$O" cat-file -t v0.2.0)" = "tag" ]
}

@test "release: a failure after files were rewritten prints how to get back to origin/main" {
  printf '#!/bin/sh\nexit 1\n' > "$R/.git/hooks/commit-msg"; chmod +x "$R/.git/hooks/commit-msg"
  run rel y 0.2.0
  [ "$status" -ne 0 ]; assert_contains "$output" "failed after modifying files"
  assert_contains "$output" "git reset --hard origin/main"
  assert_fails git -C "$O" rev-parse -q --verify refs/tags/v0.2.0
}
