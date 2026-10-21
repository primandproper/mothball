#!/usr/bin/env bash
# Runs the unit tests on an iOS simulator.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/simulator.sh
source "$root/scripts/simulator.sh"

sim="${IOS_SIM:-iPhone 17 Pro}"
udid="$(simulator_udid "$sim")"
if [[ -z "$udid" ]]; then
  echo "no available simulator named '$sim' (override with IOS_SIM=...)" >&2
  exit 1
fi

xcodebuild \
  -project "$root/Mothball.xcodeproj" \
  -scheme Mothball \
  -destination "id=$udid" \
  -quiet \
  test
