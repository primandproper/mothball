#!/usr/bin/env bash
# Runs the unit tests on an iOS simulator.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/simulator.sh
source "$root/scripts/simulator.sh"

udid="$(resolve_simulator)"
echo "testing on $(xcrun simctl list devices --json | jq -r --arg udid "$udid" \
  '.devices[][] | select(.udid == $udid) | .name') ($udid)"

# Signing is off so this runs anywhere, including CI machines with no signing identity.
xcodebuild \
  -project "$root/Mothball.xcodeproj" \
  -scheme Mothball \
  -destination "id=$udid" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  test
