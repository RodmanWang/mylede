#!/bin/sh
set -eu
[ "$#" -eq 3 ] || exit 2
FILE="$1"; EXPECTED="$2"; EXPECTED_SIZE="$3"
[ -s "$FILE" ] || { logger -t myupdate '固件文件不存在或为空'; exit 1; }
case "$EXPECTED" in *[!A-Fa-f0-9]*|'') exit 1;; esac
[ "${#EXPECTED}" -eq 64 ] || exit 1
case "$EXPECTED_SIZE" in ''|*[!0-9]*) exit 1;; esac
ACTUAL_SIZE="$(wc -c < "$FILE" | tr -d ' ')"
[ "$ACTUAL_SIZE" = "$EXPECTED_SIZE" ] || { logger -t myupdate '固件大小与 Manifest 不匹配'; exit 1; }
ACTUAL="$(sha256sum "$FILE" | awk '{print $1}')"
[ "$(printf '%s' "$ACTUAL" | tr A-F a-f)" = "$(printf '%s' "$EXPECTED" | tr A-F a-f)" ] || { logger -t myupdate '固件 SHA256 不匹配'; exit 1; }
printf '%s\n' "$ACTUAL"
