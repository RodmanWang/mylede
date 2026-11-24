#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
DEVICE="$ROOT/device"
DISK="$DEVICE/sys/devices/platform/test/block/sda"
mkdir -p "$DEVICE/proc" "$DEVICE/dev" "$DEVICE/sys/class/block" "$DISK/sda1" "$DISK/sda2"
printf '%s\n' '/dev/sda2 /rom squashfs ro,relatime 0 0' > "$DEVICE/proc/mounts"
: > "$DEVICE/dev/sda2"
printf '1\n' > "$DISK/sda1/partition"
printf '131072\n' > "$DISK/sda1/size"
printf '2\n' > "$DISK/sda2/partition"
printf '917504\n' > "$DISK/sda2/size"
ln -s "$DISK/sda1" "$DEVICE/sys/class/block/sda1"
ln -s "$DISK/sda2" "$DEVICE/sys/class/block/sda2"

CHECK="$GITHUB_WORKSPACE/luci-app-myupdate/root/usr/libexec/myupdate/check-partition-layout.sh"
export MYUPDATE_ROOT="$DEVICE"

# Equal partition sizes are sufficient.
sh "$CHECK" 64 448

# The kernel partition is too small: reject.
if sh "$CHECK" 65 448; then
  echo "Undersized kernel partition was unexpectedly accepted." >&2
  exit 1
fi

# The rootfs partition is too small: reject.
if sh "$CHECK" 64 449; then
  echo "Undersized rootfs partition was unexpectedly accepted." >&2
  exit 1
fi

# Both target partitions smaller than the installed partitions are accepted.
sh "$CHECK" 32 256

echo "x86 partition capacity checks passed."
