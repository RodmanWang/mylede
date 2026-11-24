#!/bin/sh
set -eu

CONFIG=/etc/sysupgrade.conf
BEGIN='# BEGIN MYUPDATE CUSTOM KEEP PATHS'
END='# END MYUPDATE CUSTOM KEEP PATHS'
TMP="$(mktemp /tmp/myupdate-sysupgrade-conf.XXXXXX)"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

[ ! -L "$CONFIG" ] || { echo "Refusing symlinked $CONFIG" >&2; exit 1; }
if [ -f "$CONFIG" ]; then
	sed "/^$BEGIN$/,/^$END$/d" "$CONFIG" > "$TMP"
else
	: > "$TMP"
fi

printf '\n%s\n' "$BEGIN" >> "$TMP"
# Preserve the daily unattended-upgrade guard across sysupgrade reboots.
if [ -f /etc/myupdate/last-auto-upgrade-date ]; then
	printf '%s\n' /etc/myupdate/last-auto-upgrade-date >> "$TMP"
fi
# `uci get` joins UCI list values with spaces. Spaces are forbidden by the
# path validator, so split both that representation and legacy newline text.
KEEP_PATHS="$(uci -q get myupdate.main.custom_keep_paths 2>/dev/null || true)"
while IFS= read -r path; do
	[ -n "$path" ] || continue
	case "$path" in
		/*) ;;
		*) echo "Invalid custom sysupgrade path: $path" >&2; exit 1 ;;
	esac
	case "$path" in
		/|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/tmp|/tmp/*|/rom|/rom/*|/overlay|/overlay/*)
			echo "Refusing unsafe custom sysupgrade path: $path" >&2
			exit 1
			;;
		*'/../'*|*/..|*'/./'*|*/.|*//*|*[!A-Za-z0-9_./@+-]*)
			echo "Invalid custom sysupgrade path: $path" >&2
			exit 1
			;;
	esac
	if [ -L "$path" ]; then
		echo "Refusing symlinked custom sysupgrade path: $path" >&2
		exit 1
	elif [ -f "$path" ] || [ -d "$path" ]; then
		RESOLVED="$(readlink -f "$path" 2>/dev/null || true)"
		[ "$RESOLVED" = "$path" ] || { echo "Refusing non-canonical custom sysupgrade path: $path" >&2; exit 1; }
		printf '%s\n' "$path" >> "$TMP"
	elif [ -e "$path" ]; then
		echo "Refusing special custom sysupgrade path: $path" >&2
		exit 1
	else
		echo "Skipping missing custom sysupgrade path: $path" >&2
	fi
done <<EOF
$(printf '%s\n' "$KEEP_PATHS" | tr ' ' '\n')
EOF

printf '%s\n' "$END" >> "$TMP"
chmod 600 "$TMP"
mv "$TMP" "$CONFIG"
trap - EXIT HUP INT TERM
