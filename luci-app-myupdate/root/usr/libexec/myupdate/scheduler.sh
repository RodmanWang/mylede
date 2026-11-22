#!/bin/sh
set -eu
umask 077

LAST_RUN=/etc/myupdate/last-auto-upgrade-date
R=/tmp/myupdate
mkdir -p "$R" /etc/myupdate
chmod 700 "$R" /etc/myupdate

run_notify_check() {
	/usr/libexec/myupdate/task.sh check >/dev/null 2>&1 || logger -t myupdate "定时更新检查失败"
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
	if ! /usr/libexec/myupdate/task.sh check; then
		logger -t myupdate "自动升级：更新检查失败，今日不再重试"
		return 0
	fi

	AVAILABLE="$(jsonfilter -i "$R/status.json" -e '@.update_available' 2>/dev/null || echo false)"
	[ "$AVAILABLE" = true ] || {
		logger -t myupdate "自动升级：没有发现可用的新版本"
		return 0
	}

	if ! /usr/libexec/myupdate/task.sh download; then
		logger -t myupdate "自动升级：下载或固件验证失败，已取消刷写"
		return 0
	fi

	if ! /usr/libexec/myupdate/task.sh upgrade; then
		logger -t myupdate "自动升级：sysupgrade 预检查或刷写启动失败"
		return 0
	fi
	logger -t myupdate "自动升级任务已交给 sysupgrade"
}

while :; do
	MODE="$(uci -q get myupdate.main.upgrade_mode || echo manual)"
	INTERVAL="$(uci -q get myupdate.main.check_interval || echo 21600)"
	case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=21600;; esac
	[ "$INTERVAL" -ge 900 ] 2>/dev/null && [ "$INTERVAL" -le 604800 ] 2>/dev/null || INTERVAL=21600

	case "$MODE" in
		notify)
			run_notify_check
			ELAPSED=0
			while [ "$ELAPSED" -lt "$INTERVAL" ]; do sleep 30; ELAPSED=$((ELAPSED + 30)); done
			;;
		auto)
			run_auto_upgrade
			sleep 30
			;;
		*)
			sleep 30
			;;
	esac
done
