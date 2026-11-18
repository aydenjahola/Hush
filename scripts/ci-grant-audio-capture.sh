#!/bin/bash
# Experimental, CI only: tries to grant Audio Recording (kTCCServiceAudioCapture) to the processes
# that run `make integration-test` on a GitHub-hosted macOS runner, by writing TCC.db directly.
#
# This only works when System Integrity Protection is disabled (the system TCC.db is SIP-protected)
# and the TCC.db schema matches what's written below. It never fails the job: if the grant doesn't
# take, the integration tests skip themselves with the permission message instead of prompting.
#
# Never run this on your own Mac. Grant permission in System Settings instead (see https://aydenjahola.github.io/Hush/contributing/testing/#integration-tests).

set -u

SERVICE="kTCCServiceAudioCapture"
SYSTEM_DB="/Library/Application Support/com.apple.TCC/TCC.db"
USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

log() { printf '[grant-audio-capture] %s\n' "$*"; }

if [ "$(uname -s)" != "Darwin" ]; then
    log "Not macOS; nothing to do."
    exit 0
fi

sip_status="$(csrutil status 2>&1 || true)"
log "csrutil: $sip_status"
case "$sip_status" in
    *disabled*) ;;
    *)
        log "SIP is enabled, so TCC.db can't be written. Skipping; the integration tests will report themselves as skipped."
        exit 0
        ;;
esac

# Candidate clients: the shells the workflow runs, the runner's own processes (TCC attributes a
# child to its responsible process) and the Swift test runners. Missing paths are skipped.
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
candidates=(
    /bin/bash
    /bin/zsh
    /bin/sh
    /usr/bin/env
    /usr/local/opt/runner/provisioner/provisioner
    /opt/hca/hosted-compute-agent
    "$developer_dir/usr/bin/xctest"
    "$developer_dir/usr/libexec/swift/pm/swiftpm-testing-helper"
    "$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
)
for worker in "$HOME"/runners/*/bin/Runner.Worker "$HOME"/actions-runner/bin/Runner.Worker; do
    candidates+=("$worker")
done

clients=()
for path in "${candidates[@]}"; do
    if [ -e "$path" ]; then
        clients+=("$path")
    fi
done
log "Clients to grant (${#clients[@]}):"
for client in "${clients[@]}"; do
    log "  $client"
done

# Inserts with named columns, so it works across the schema versions that share these columns.
# client_type 1 = absolute path; auth_value 2 = allowed; auth_reason 4 = set by system policy.
grant() {
    local db="$1" sudo_cmd="$2" client="$3" escaped now sql
    escaped="${client//\'/\'\'}"
    now="$(date +%s)"
    sql="INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags, last_modified) VALUES ('$SERVICE', '$escaped', 1, 2, 4, 1, 'UNUSED', 0, $now);"
    if $sudo_cmd sqlite3 "$db" "$sql" 2>&1; then
        log "  granted $client"
        return 0
    fi
    log "  FAILED for $client"
    return 1
}

granted=0
try_db() {
    local db="$1" sudo_cmd="$2" label="$3"
    if ! $sudo_cmd test -f "$db"; then
        log "$label TCC.db not found at $db"
        return
    fi
    log "$label TCC.db schema (access table columns):"
    $sudo_cmd sqlite3 "$db" "PRAGMA table_info(access);" 2>&1 | awk -F'|' '{ printf "  %s", $2 } END { print "" }'
    for client in "${clients[@]}"; do
        if grant "$db" "$sudo_cmd" "$client"; then
            granted=$((granted + 1))
        fi
    done
    log "$label TCC.db rows for $SERVICE now:"
    $sudo_cmd sqlite3 "$db" "SELECT client, auth_value FROM access WHERE service = '$SERVICE';" 2>&1 | sed 's/^/  /'
}

try_db "$SYSTEM_DB" sudo "System"
try_db "$USER_DB" "" "User"

if [ "$granted" -gt 0 ]; then
    log "Wrote $granted grant(s). tccd caches decisions; restarting it so they apply."
    sudo killall tccd 2>/dev/null || true
    killall tccd 2>/dev/null || true
else
    log "No grants were written; the integration tests will skip with the permission message."
fi
exit 0
