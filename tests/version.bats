#!/usr/bin/env bats
load test_helper
setup() { setup_env; }

copy_tree() {   # DIR [VERSION_CONTENT] → a copy of bin/ and lib/ with an optional VERSION file
  mkdir -p "$1"
  cp -R "$SIMLANE_ROOT/bin" "$SIMLANE_ROOT/lib" "$1/"
  if [ $# -gt 1 ]; then printf '%b' "$2" > "$1/VERSION"; fi
}

@test "VERSION is a plain X.Y.Z" {
  grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$SIMLANE_ROOT/VERSION"
}

@test "--version, -V and version print the VERSION file" {
  want=$(tr -d '[:space:]' < "$SIMLANE_ROOT/VERSION")
  run "$SIMLANE" --version; [ "$status" -eq 0 ]; [ "$output" = "$want" ]
  run "$SIMLANE" -V;        [ "$status" -eq 0 ]; [ "$output" = "$want" ]
  run "$SIMLANE" version;   [ "$status" -eq 0 ]; [ "$output" = "$want" ]
}

@test "--version strips surrounding whitespace and blank lines" {
  copy_tree "$TD/t" ' 0.9.1 \n\n'
  run "$TD/t/bin/simlane" --version
  [ "$status" -eq 0 ]; [ "$output" = "0.9.1" ]
}

@test "--version fails clearly when VERSION is missing" {
  copy_tree "$TD/t"
  run "$TD/t/bin/simlane" --version
  [ "$status" -eq 1 ]; assert_contains "$output" "VERSION file not found"
}

@test "help lists the version command" {
  run "$SIMLANE" help
  assert_contains "$output" "--version"
}
