#!/bin/sh
set -eu

task_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_build=$(mktemp -d /tmp/moonlight-window-test.XXXXXX)
trap 'rm -f "$task_build/stream-window-recovery-regression"; rmdir "$task_build"' EXIT

swiftc "$task_repo/Moonlight Vision/StreamWindowRecoveryState.swift" \
    "$task_repo/Tests/stream-window-recovery-regression.swift" \
    -o "$task_build/stream-window-recovery-regression"
"$task_build/stream-window-recovery-regression"
