#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; CS="$SIMLANE_ROOT/scripts/changelog-section.sh"; CR="$SIMLANE_ROOT/scripts/check-release.sh"
  R="$TD/r"; mkdir -p "$R"
  printf '%s\n' '# Changelog' '' '## Unreleased' '' '- next thing' '' '## 0.2.0 — 2026-10-04' '' '- a' '- b' '' \
    '## 0.1.0 — 2026-10-03' '' '- first' > "$R/CHANGELOG.md"
  echo 0.2.0 > "$R/VERSION"
}

@test "changelog-section: prints one version's body without the heading or surrounding blank lines" {
  run "$CS" 0.2.0 "$R/CHANGELOG.md"
  [ "$status" -eq 0 ]; [ "$output" = "$(printf '%s\n%s' '- a' '- b')" ]
  run "$CS" 0.1.0 "$R/CHANGELOG.md"; [ "$output" = "- first" ]
  run "$CS" Unreleased "$R/CHANGELOG.md"; [ "$output" = "- next thing" ]
}

@test "changelog-section: a missing section exits 1" {
  run "$CS" 9.9.9 "$R/CHANGELOG.md"; [ "$status" -eq 1 ]; assert_contains "$output" "no '## 9.9.9' section"
}

@test "changelog-section: a section with only blank lines counts as empty" {
  printf '%s\n' '# Changelog' '' '## Unreleased' '' '   ' '' '## 0.1.0 — 2026-10-03' '' '- first' > "$R/CHANGELOG.md"
  run "$CS" Unreleased "$R/CHANGELOG.md"; [ "$status" -eq 1 ]; assert_contains "$output" "is empty"
}

@test "check-release: tag, VERSION and newest CHANGELOG section agree" {
  run "$CR" v0.2.0 "$R"; [ "$status" -eq 0 ]; assert_contains "$output" "v0.2.0 ok"
}

@test "check-release: VERSION with surrounding whitespace still matches" {
  printf ' 0.2.0 \n\n' > "$R/VERSION"
  run "$CR" v0.2.0 "$R"; [ "$status" -eq 0 ]
}

@test "check-release: rejects a malformed tag, a VERSION mismatch and a CHANGELOG mismatch" {
  run "$CR" 0.2.0 "$R";   [ "$status" -eq 1 ]; assert_contains "$output" "not a release tag"
  run "$CR" v0.2 "$R";    [ "$status" -eq 1 ]; assert_contains "$output" "not a release tag"
  echo 0.3.0 > "$R/VERSION"
  run "$CR" v0.3.0 "$R";  [ "$status" -eq 1 ]; assert_contains "$output" "newest CHANGELOG section is 0.2.0"
  run "$CR" v0.2.0 "$R";  [ "$status" -eq 1 ]; assert_contains "$output" "VERSION is 0.3.0"
}

@test "check-release: a missing VERSION file fails" {
  rm "$R/VERSION"
  run "$CR" v0.2.0 "$R"; [ "$status" -eq 1 ]; assert_contains "$output" "VERSION file missing"
}
