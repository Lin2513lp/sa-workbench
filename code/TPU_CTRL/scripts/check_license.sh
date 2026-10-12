#!/usr/bin/env bash
set -eu
if [ "$#" -ne 6 ]; then
    echo "ERROR: check_license.sh requires 6 arguments; received $#." >&2
    exit 2
fi
server=$1
license_file=$2
lmutil=$3
lmgrd=$4
log_dir=$5
lock_file=$6
mkdir -p "$log_dir" "$(dirname "$lock_file")"
exec 9>"$lock_file"
flock -w 30 9 || { echo "ERROR: another license recovery is still running"; exit 1; }
status_log="$log_dir/license_status.log"
daemon_log="$log_dir/license_daemon.log"
license_ok() {
    timeout 3 "$lmutil" lmstat -a -c "$server" >"$status_log" 2>&1 || true
    grep -Eq 'snpslmd: UP' "$status_log"
}
test -x "$lmutil" || { echo "ERROR: lmutil missing: $lmutil"; exit 1; }
if license_ok; then
    echo "[LICENSE] UP: $server"
    exit 0
fi
case "$server" in
    27000@localhost.localdomain|27000@localhost|27000@127.0.0.1) ;;
    *) echo "ERROR: license server unavailable: $server (no local recovery for remote/custom server)"; cat "$status_log"; exit 1 ;;
esac
test -f "$license_file" || { echo "ERROR: license file missing: $license_file"; exit 1; }
test -x "$lmgrd" || { echo "ERROR: lmgrd missing: $lmgrd"; exit 1; }
echo "[LICENSE] Checking local daemon; using existing license file: $license_file"
if pgrep -u "$(id -u)" -x lmgrd >/dev/null; then
    echo "[LICENSE] Existing lmgrd; requesting reread"
    timeout 5 "$lmutil" lmreread -c "$server" >>"$daemon_log" 2>&1 || true
else
    echo "[LICENSE] Starting local lmgrd"
    nohup "$lmgrd" -c "$license_file" -l "$daemon_log" </dev/null >/dev/null 2>&1 9>&- &
fi
deadline=$((SECONDS + 20))
while [ "$SECONDS" -lt "$deadline" ]; do
    if license_ok; then
        echo "[LICENSE] UP: $server"
        exit 0
    fi
    sleep 1
done
echo "ERROR: license server still unavailable; VCS will not be started."
cat "$status_log"
if [ -f "$daemon_log" ]; then tail -n 25 "$daemon_log"; fi
exit 1
