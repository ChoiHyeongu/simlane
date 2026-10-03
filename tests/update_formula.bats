#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; U="$SIMLANE_ROOT/scripts/update-formula.sh"; F="$TD/simlane.rb"
  SHA_A=$(printf 'a%.0s' $(seq 64)); SHA_B=$(printf 'b%.0s' $(seq 64))
  cat > "$F" <<RB
class Simlane < Formula
  desc "One iOS simulator + Metro lane per git worktree"
  homepage "https://github.com/ChoiHyeongu/simlane"
  url "https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "$SHA_A"
  license "MIT"
end
RB
}

@test "update-formula: rewrites url and sha256, then reports unchanged on a repeat" {
  run "$U" "$F" 0.2.0 "$SHA_B"; [ "$status" -eq 0 ]; [ "$output" = "updated" ]
  grep -qx '  url "https://github.com/ChoiHyeongu/simlane/archive/refs/tags/v0.2.0.tar.gz"' "$F"
  grep -qx "  sha256 \"$SHA_B\"" "$F"
  grep -qx '  license "MIT"' "$F"
  run "$U" "$F" 0.2.0 "$SHA_B"; [ "$status" -eq 0 ]; [ "$output" = "unchanged" ]
}

@test "update-formula: rejects a bad version or sha256 without touching the file" {
  before=$(cat "$F")
  run "$U" "$F" v0.2.0 "$SHA_B"; [ "$status" -eq 1 ]; assert_contains "$output" "bad version"
  run "$U" "$F" 0.2.0 abc;       [ "$status" -eq 1 ]; assert_contains "$output" "bad sha256"
  [ "$(cat "$F")" = "$before" ]
}

@test "update-formula: refuses a formula without exactly one url and one sha256 line" {
  printf '%s\n' 'class Simlane < Formula' '  sha256 "x"' 'end' > "$F"
  run "$U" "$F" 0.2.0 "$SHA_B"; [ "$status" -eq 1 ]; assert_contains "$output" "exactly one"
}
