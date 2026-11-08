#!/bin/sh
# get_busybox.sh <rooted-serial> [dest]
#
# Pulls Magisk's busybox off a rooted phone: busybox is GPL-2.0, so this repository does not ship
# it; this is the convenient way to obtain a matching, tested binary for another device.
set -eu
[ -n "${MSYSTEM:-}" ] && export MSYS_NO_PATHCONV=1
serial=${1:-}
dest=${2:-out/busybox}
[ -n "$serial" ] || { echo "usage: get_busybox.sh <rooted-serial> [dest]" >&2; exit 64; }
[ "$(adb -s "$serial" shell id -u | tr -d '\r')" = 0 ] || { echo "get_busybox: $serial is not root" >&2; exit 1; }
mkdir -p "$(dirname -- "$dest")"
adb -s "$serial" shell "su -c 'cp /data/adb/magisk/busybox /sdcard/Download/openar-busybox && chmod 644 /sdcard/Download/openar-busybox'"
adb -s "$serial" pull /sdcard/Download/openar-busybox "$dest" >/dev/null
adb -s "$serial" shell "rm -f /sdcard/Download/openar-busybox"
echo "$dest"
