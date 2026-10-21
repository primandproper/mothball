#!/usr/bin/env bash
# Builds the app, installs it on a simulator with contacts access pre-granted, seeds the
# "Mothball NoteTest" contact, runs the round-trip spike, and prints its report.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/simulator.sh
source "$root/scripts/simulator.sh"

bundle_id="software.primandproper.mothball"
timeout_seconds="${SPIKE_TIMEOUT:-60}"
udid="$(resolve_simulator)"

derived="$(mktemp -d)"
trap 'rm -rf "$derived"' EXIT

echo "building for $udid"
xcodebuild \
  -project "$root/Mothball.xcodeproj" \
  -scheme Mothball \
  -destination "id=$udid" \
  -derivedDataPath "$derived" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  build

boot_simulator "$udid"
xcrun simctl install "$udid" "$derived/Build/Products/Debug-iphonesimulator/Mothball.app"
xcrun simctl privacy "$udid" grant contacts "$bundle_id"
xcrun simctl addmedia "$udid" "$root/fixtures/note-test.vcf"

data="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
report="$data/Documents/spike-report.json"
rm -f "$report"

xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
xcrun simctl launch "$udid" "$bundle_id" -runSpike >/dev/null

deadline=$((SECONDS + timeout_seconds))
until [[ -f "$report" ]]; do
  if ((SECONDS >= deadline)); then
    echo "no report after ${timeout_seconds}s; check Console.app for subsystem $bundle_id" >&2
    exit 1
  fi
  sleep 1
done

jq -r '.steps[] | "[\(.outcome)] \(.name)", (.details[] | "    \(.)")' "$report"
