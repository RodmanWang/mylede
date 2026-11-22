#!/bin/sh
set -eu
umask 077

R="${MYUPDATE_RUNTIME_DIR:-/tmp/myupdate}"
CONFIG_DIR="${MYUPDATE_CONFIG_DIR:-/etc/myupdate}"
LAST_RUN="${MYUPDATE_LAST_RUN_FILE:-$CONFIG_DIR/last-auto-upgrade-date}"
TASK_SCRIPT="${MYUPDATE_TASK_SCRIPT:-/usr/libexec/myupdate/task.sh}"
mkdir -p "$R" "$CONFIG_DIR"
chmod 700 "$R" "$CONFIG_DIR"

process_manual_request() {
	REQUEST_DIR="$R/request"
	[ -d "$REQUEST_DIR" ] || return 0
	# Never consume a request while another task owns the execution lock.
	[ ! -d "$R/task.lock" ] || return 0
	[ -f "$REQUEST_DIR/action" ] || {
		rm -rf "$REQUEST_DIR"
		logger -t myupdate "丢弃不完整的任务请求"
		return 0
	}

	REQUEST_ACTION="$(cat "$REQUEST_DIR/action" 2>/dev/null || true)"
	case "$REQUEST_ACTION" in
		check|download|upgrade) ;;
		*)
			rm -rf "$REQUEST_DIR"
			logger -t myupdate "丢弃无效的任务请求"
			return 0
			;;
	esac

	# The request directory is atomically published by rpcd, so it is safe to
	# remove it before running the task. task.sh creates its own execution lock.
	rm -rf "$REQUEST_DIR"
	logger -t myupdate "开始执行 LuCI 请求的任务：$REQUEST_ACTION"
	"$TASK_SCRIPT" "$REQUEST_ACTION" || logger -t myupdate "LuCI 请求的任务执行失败：$REQUEST_ACTION"
}

wait_interval() {
	WAIT_SECONDS="$1"
	ELAPSED=0
	while [ "$ELAPSED" -lt "$WAIT_SECONDS" ]; do
		sleep 1
		ELAPSED=$((ELAPSED + 1))
		process_manual_request
	done
}

run_notify_check() {
	"$TASK_SCRIPT" check >/dev/null 2>&1 || logger -t myupdate "定时更新检查失败"
}

run_auto_upgrade() {
	TODAY="$(date +%F)"
	NOW="$(date +%H%M)"
	AUTO_TIME="$(uci -q get myupdate.main.auto_upgrade_time || echo 04:00)"
	case "$AUTO_TIME" in
		[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;;
		*) AUTO_TIME=04:00 ;;
	esac
	AT="$(printf '%s' "$AUTO_TIME" | tr -d ':')"
	[ "$(cat "$LAST_RUN" 2>/dev/null || true)" != "$TODAY" ] || return 0
	awk -v now="$NOW" -v at="$AT" 'BEGIN { exit !(now + 0 >= at + 0) }' || return 0

	# Persist the daily guard before starting work. A reboot or scheduler restart
	# must not cause a second unattended flash on the same calendar day.
	printf '%s\n' "$TODAY" > "$LAST_RUN.tmp"
	chmod 600 "$LAST_RUN.tmp"
	mv "$LAST_RUN.tmp" "$LAST_RUN"

	logger -t myupdate "开始每日自动升级流程（计划时间 $AUTO_TIME）"
	if ! "$TASK_SCRIPT" check; then
		logger -t myupdate "自动升级：更新检查失败，今日不再重试"
		return 0
	fi

	AVAILABLE="$(jsonfilter -i "$R/status.json" -e '@.update_available' 2>/dev/null || echo false)"
	[ "$AVAILABLE" = true ] || {
		logger -t myupdate "自动升级：没有发现可用的新版本"
		return 0
	}

	if ! "$TASK_SCRIPT" download; then
		logger -t myupdate "自动升级：下载或固件验证失败，已取消刷写"
		return 0
	fi

	if ! "$TASK_SCRIPT" upgrade; then
		logger -t myupdate "自动升级：sysupgrade 预检查或刷写启动失败"
		return 0
	fi
	logger -t myupdate "自动升级任务已交给 sysupgrade"
}

while :; do
	process_manual_request
	MODE="$(uci -q get myupdate.main.upgrade_mode || echo manual)"
	INTERVAL="$(uci -q get myupdate.main.check_interval || echo 86400)"
	case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=86400;; esac
	[ "$INTERVAL" -ge 900 ] 2>/dev/null && [ "$INTERVAL" -le 604800 ] 2>/dev/null || INTERVAL=86400

	case "$MODE" in
		notify)
			run_notify_check
			wait_interval "$INTERVAL"
			;;
		auto)
			run_auto_upgrade
			wait_interval 1
			;;
		*)
			wait_interval 1
			;;
	esac
done
