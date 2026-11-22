#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
SCHEDULER="$REPO_ROOT/luci-app-myupdate/root/usr/libexec/myupdate/scheduler.sh"
TMP="$(mktemp -d)"
SCHED_PID=""

cleanup() {
	if [ -n "$SCHED_PID" ]; then
		kill "$SCHED_PID" 2>/dev/null || true
		wait "$SCHED_PID" 2>/dev/null || true
	fi
	rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP/bin"
cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
case "$*" in
	*upgrade_mode*) printf '%s' manual ;;
	*check_interval*) printf '%s' 86400 ;;
	*) exit 1 ;;
esac
EOF
cat > "$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$TMP/fake-task.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$MYUPDATE_TEST_LOG"
EOF
chmod 0755 "$TMP/bin/uci" "$TMP/bin/logger" "$TMP/fake-task.sh"

export PATH="$TMP/bin:$PATH"
export MYUPDATE_RUNTIME_DIR="$TMP/runtime"
export MYUPDATE_CONFIG_DIR="$TMP/config"
export MYUPDATE_LAST_RUN_FILE="$TMP/config/last-run"
export MYUPDATE_TASK_SCRIPT="$TMP/fake-task.sh"
export MYUPDATE_TEST_LOG="$TMP/task.log"

sh "$SCHEDULER" &
SCHED_PID="$!"

# A queued check request must be consumed and dispatched exactly once.
mkdir -p "$MYUPDATE_RUNTIME_DIR/request"
printf '%s\n' check > "$MYUPDATE_RUNTIME_DIR/request/action"
attempt=0
while [ "$attempt" -lt 8 ] && [ ! -s "$MYUPDATE_TEST_LOG" ]; do
	sleep 1
	attempt=$((attempt + 1))
done
[ -s "$MYUPDATE_TEST_LOG" ] || { echo "scheduler did not dispatch queued request" >&2; exit 1; }
[ "$(cat "$MYUPDATE_TEST_LOG")" = check ] || { echo "unexpected task action" >&2; exit 1; }
[ ! -e "$MYUPDATE_RUNTIME_DIR/request" ] || { echo "request was not consumed" >&2; exit 1; }

# A request must remain queued while another task owns the task lock.
mkdir -p "$MYUPDATE_RUNTIME_DIR/task.lock"
mkdir -p "$MYUPDATE_RUNTIME_DIR/request"
printf '%s\n' download > "$MYUPDATE_RUNTIME_DIR/request/action"
sleep 2
[ -d "$MYUPDATE_RUNTIME_DIR/request" ] || { echo "request was consumed while task lock was held" >&2; exit 1; }
[ "$(wc -l < "$MYUPDATE_TEST_LOG" | tr -d ' ')" = 1 ] || { echo "task ran while task lock was held" >&2; exit 1; }

rmdir "$MYUPDATE_RUNTIME_DIR/task.lock"
attempt=0
while [ "$attempt" -lt 8 ] && [ "$(wc -l < "$MYUPDATE_TEST_LOG" | tr -d ' ')" -lt 2 ]; do
	sleep 1
	attempt=$((attempt + 1))
done
[ "$(cat "$MYUPDATE_TEST_LOG")" = "$(printf 'check\ndownload')" ] || {
	echo "queued request was not dispatched after lock release" >&2
	exit 1
}

echo "MyUpdate scheduler queue tests passed."
