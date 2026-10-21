#!/usr/bin/env bash
# Shared helpers for scripts that drive the iOS simulator. Source this file; don't run it.

default_simulator="iPhone 17 Pro"

# Prints the UDID of the first available simulator whose name is exactly $1.
simulator_udid() {
  local name="$1"
  xcrun simctl list devices available --json |
    jq -r --arg name "$name" \
      '[.devices[][] | select(.name == $name)] | first | .udid // empty'
}

# Prints the UDID to run on. IOS_SIM, when set, must name an available simulator exactly.
# Otherwise this tries the default device, then falls back to the first available iPhone, since
# CI images don't always carry the default.
resolve_simulator() {
  local udid
  if [[ -n "${IOS_SIM:-}" ]]; then
    udid="$(simulator_udid "$IOS_SIM")"
    if [[ -z "$udid" ]]; then
      echo "no available simulator named '$IOS_SIM'" >&2
      return 1
    fi
    echo "$udid"
    return
  fi

  udid="$(simulator_udid "$default_simulator")"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl list devices available --json |
      jq -r '[.devices[][] | select(.name | startswith("iPhone"))] | first | .udid // empty')"
  fi
  if [[ -z "$udid" ]]; then
    echo "no available iPhone simulator (set IOS_SIM to pick one)" >&2
    return 1
  fi
  echo "$udid"
}

# Boots the simulator if it isn't already running, then waits for it to finish booting.
boot_simulator() {
  local udid="$1"
  xcrun simctl bootstatus "$udid" -b >/dev/null
}
