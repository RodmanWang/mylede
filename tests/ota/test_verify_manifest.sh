#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"
SYSROOT="$ROOT/device"
mkdir -p "$BIN" "$SYSROOT/etc" "$SYSROOT/sys/firmware/efi" "$SYSROOT/tmp/myupdate"

cat > "$SYSROOT/etc/openwrt_release" <<'RELEASE'
DISTRIB_TARGET='x86/64'
DISTRIB_ARCH='x86_64'
RELEASE

cat > "$ROOT/uci" <<'UCI'
#!/bin/sh
case "$*" in
  *minisign_public_key*) cat "$TEST_PUBLIC_KEY" ;;
  *) exit 1 ;;
esac
UCI
cat > "$ROOT/ubus" <<'UBUS'
#!/bin/sh
printf '%s\n' '{"rootfs_type":"squashfs"}'
UBUS
cat > "$ROOT/jsonfilter" <<'JSONFILTER'
#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
path = None
expr = None
while args:
    arg = args.pop(0)
    if arg == "-i":
        path = args.pop(0)
    elif arg == "-e":
        expr = args.pop(0)
if not expr:
    raise SystemExit(2)
data = json.load(open(path, encoding="utf-8")) if path else json.load(sys.stdin)
value = data
for key in expr.lstrip("@").strip(".").split("."):
    if key:
        value = value[key]
if isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
elif value is not None:
    print(value)
JSONFILTER
chmod +x "$ROOT/uci" "$ROOT/ubus" "$ROOT/jsonfilter"

minisign -G -W -s "$ROOT/minisign.sec" -p "$ROOT/minisign.pub" >/dev/null
PUBLIC_KEY="$(tail -n 1 "$ROOT/minisign.pub")"
printf '%s\n' "$PUBLIC_KEY" > "$ROOT/public-key"

cat > "$ROOT/manifest.json" <<'MANIFEST'
{
  "schema_version": 1,
  "version": "2026.11.22.123.1",
  "tag": "v2026.11.22.123.1",
  "channel": "stable",
  "compatibility": {
    "target": "x86",
    "subtarget": "64",
    "arch": "x86_64",
    "device_policy": "target",
    "devices": []
  },
  "image": {
    "asset": "openwrt-x86-64-generic-squashfs-combined-efi.img.gz",
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "size": 123
  }
}
MANIFEST

minisign -S -W -s "$ROOT/minisign.sec" -m "$ROOT/manifest.json" -x "$ROOT/manifest.minisig" >/dev/null
export TEST_PUBLIC_KEY="$ROOT/public-key"
export PATH="$ROOT:$PATH"
export MYUPDATE_ROOT="$SYSROOT"
VERIFY="$GITHUB_WORKSPACE/luci-app-myupdate/root/usr/libexec/myupdate/verify-manifest.sh"

sh "$VERIFY" "$ROOT/manifest.json" "$ROOT/manifest.minisig" "v2026.11.22.123.1" stable
grep -qx '2026.11.22.123.1' "$SYSROOT/tmp/myupdate/verified-manifest.txt"

if sh "$VERIFY" "$ROOT/manifest.json" "$ROOT/manifest.minisig" "v2026.11.22.123.2" stable; then
  echo "Manifest Tag mismatch was unexpectedly accepted." >&2
  exit 1
fi

cp "$ROOT/manifest.minisig" "$ROOT/tampered.minisig"
printf 'tamper\n' >> "$ROOT/tampered.minisig"
if sh "$VERIFY" "$ROOT/manifest.json" "$ROOT/tampered.minisig" "v2026.11.22.123.1" stable; then
  echo "Tampered Minisign signature was unexpectedly accepted." >&2
  exit 1
fi

echo "OTA manifest signature, Tag, and x86_64 UEFI/squashfs compatibility tests passed."
