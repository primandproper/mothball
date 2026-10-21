#!/usr/bin/env bash
# Shared helpers for scripts that drive the iOS simulator. Source this file; don't run it.

# Prints the UDID of the first available simulator whose name is exactly $1.
simulator_udid() {
  local name="$1"
  xcrun simctl list devices available --json |
    jq -r --arg name "$name" \
      '[.devices[][] | select(.name == $name)] | first | .udid // empty'
}

# Boots the simulator if it isn't already running, then waits for it to finish booting.
boot_simulator() {
  local udid="$1"
  xcrun simctl bootstatus "$udid" -b >/dev/null
}
