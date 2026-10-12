#!/bin/sh
# Local paired-CoreDevice bridge. No server, network token, or cloud upload.
set -eu
umask 077
task_device=${1:?Provide the paired Vision Pro identifier}
task_root=${2:?Provide an absolute diagnostics output directory}
case "$task_root" in /*) ;; *) exit 2 ;; esac
mkdir -p "$task_root/client" "$task_root/crashes"
task_work=$(mktemp -d "$task_root/.pull.XXXXXX")
cleanup() {
    # This exact directory was just created by mktemp, never a user-data root.
    case "$task_work" in "$task_root"/.pull.*) rm -rf -- "$task_work" ;; esac
}
trap cleanup EXIT HUP INT TERM

if xcrun devicectl --timeout 15 device copy from \
    --device "$task_device" --domain-type appDataContainer \
    --domain-identifier com.yufeiran.MoonlightVision \
    --source Library/Caches/YuMoonlightDiagnostics \
    --destination "$task_work/client" > "$task_work/transfer-status.txt" 2>&1; then
    if test -f "$task_work/client/sync-preference.json" && \
       jq -e '.enabled == false' "$task_work/client/sync-preference.json" >/dev/null; then
        exit 0
    fi
    ditto "$task_work/client" "$task_root/client"
fi

if xcrun devicectl --timeout 15 device info files --device "$task_device" \
    --domain-type systemCrashLogs --search 'Yu Moonlight' \
    --json-output "$task_work/inventory.json" > "$task_work/crash-status.txt" 2>&1; then
    jq -r '.result.files[]? | select(.name | startswith("Yu Moonlight-")) |
        select(.name | endswith(".ips")) | .relativePath' "$task_work/inventory.json" |
    while IFS= read -r task_name; do
        case "$task_name" in
            *'/'*|*'..'*) continue ;;
            'Yu Moonlight-'*.ips) ;;
            *) continue ;;
        esac
        if ! test -f "$task_root/crashes/$task_name"; then
            if xcrun devicectl --timeout 15 device copy from --device "$task_device" \
                --domain-type systemCrashLogs --source "$task_name" \
                --destination "$task_work/crash.ips" \
                > "$task_work/crash-copy-status.txt" 2>&1 && \
                jq -e . "$task_work/crash.ips" >/dev/null; then
                mv "$task_work/crash.ips" "$task_root/crashes/$task_name"
            fi
        fi
    done
fi
