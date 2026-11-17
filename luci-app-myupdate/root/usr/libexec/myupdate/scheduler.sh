#!/bin/sh
set -eu
umask 077
while :; do
	MODE="$(uci -q get myupdate.main.upgrade_mode || echo manual)"
	INTERVAL="$(uci -q get myupdate.main.check_interval || echo 21600)"
	case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=21600;; esac
	[ "$INTERVAL" -ge 900 ] 2>/dev/null && [ "$INTERVAL" -le 604800 ] 2>/dev/null || INTERVAL=21600
	case "$MODE" in notify|auto) /usr/libexec/myupdate/task.sh check >/dev/null 2>&1 || true;; esac
	ELAPSED=0
	while [ "$ELAPSED" -lt "$INTERVAL" ]; do sleep 30; ELAPSED=$((ELAPSED + 30)); done
done
