#!/bin/sh
set -eu
task_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build=$(mktemp -d /tmp/moonlight-diagnostic-test.XXXXXX)
trap 'rm -f "$task_build/client-diagnostics-regression" "$task_build/capture-smoke.log"; rmdir "$task_build"' EXIT
swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx14.0" \
    "$task_repo/Moonlight Vision/ClientDiagnostics.swift" \
    "$task_repo/Moonlight Vision/ClientWindowPolicy.swift" \
    "$task_repo/Tests/client-diagnostics-regression.swift" \
    -o "$task_build/client-diagnostics-regression"
"$task_build/client-diagnostics-regression"
"$task_build/client-diagnostics-regression" --capture-smoke > "$task_build/capture-smoke.log" 2>&1
# The child asserts on the actual file contents; set -e checks its exit status.
echo 'PASS: real stdout/stderr capture and sanitized disk writes'
