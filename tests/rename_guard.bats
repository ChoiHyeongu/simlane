#!/usr/bin/env bats
# Guards the rn-slot → simlane rename: no legacy identifier may survive anywhere in the repo.
load test_helper

@test "no legacy rn-slot identifiers remain in the repository" {
  cd "$SIMLANE_ROOT"
  run grep -rIn -e 'rn-slot' -e 'rnslot' -e 'RNSLOT' -e 'RN_SLOT' -e 'RN Slot' -e 'rn-parallel-dev' -e 'RN_METRO_PORT' -e 'RN_SIM_UDID' -e 'RN_BUNDLE_ID' \
    --exclude-dir=.git --exclude=rename_guard.bats .
  [ "$status" -eq 1 ]
}
