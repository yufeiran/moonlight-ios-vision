#!/bin/sh
set -eu

task_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_common="$task_repo/moonlight-common/moonlight-common-c"
task_build=$(mktemp -d /tmp/moonlight-reorder-test.XXXXXX)
trap 'rm -f "$task_build/video-reorder-regression"; rm -rf "$task_build/video-reorder-regression.dSYM"; rmdir "$task_build"' EXIT

# Native macOS harness; actual common sources are linked, with control/renderer
# callbacks replaced by counters. Dead stripping excludes unused ENet helpers.
clang -std=c11 -DLC_DEBUG -DHAS_SOCKLEN_T -D__APPLE_USE_RFC_3542 \
    -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
    -Wl,-dead_strip -Wno-unused-parameter \
    -I"$task_common/src" -I"$task_common/enet/include" -I"$task_common/reedsolomon" \
    "$task_repo/Tests/video-reorder-regression.c" \
    "$task_common/src/RtpVideoQueue.c" "$task_common/src/VideoDepacketizer.c" \
    "$task_common/src/ByteBuffer.c" "$task_common/src/LinkedBlockingQueue.c" \
    "$task_common/src/Misc.c" "$task_common/src/Platform.c" \
    "$task_common/reedsolomon/rs.c" -lpthread -o "$task_build/video-reorder-regression"

"$task_build/video-reorder-regression"
