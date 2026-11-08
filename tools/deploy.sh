#!/bin/sh
# deploy.sh <serial> [--root|--shell] [--pack generic] [--ifaces "..."] [--port N]
#
# Builds the tree, pushes it, and keeps the owner's config (etc/httpd.conf, etc/commands,
# etc/web.conf) and var/ across deploys. No root is required:
#   root  -> /data/adb/openar       (privileged features, :80 by default)
#   shell -> /data/local/tmp/openar (:8080 by default, loopback only)
# busybox is not shipped in this repo: a busybox already on the device is copied to bin/busybox.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
serial=${1:-}
[ -n "$serial" ] || { echo "usage: deploy.sh <serial> [--root|--shell] [--pack generic] [--ifaces ...] [--port N]" >&2; exit 64; }
shift
mode=""; pack="generic"; ifaces=""; port=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) mode=root ;;
        --shell) mode=shell ;;
        --pack) pack=$2; shift ;;
        --ifaces) ifaces=$2; shift ;;
        --port) port=$2; shift ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done
if [ -z "$mode" ]; then
    if [ "$(adb -s "$serial" shell id -u | tr -d '\r')" = 0 ]; then mode=root; else mode=shell; fi
fi
if [ "$mode" = root ]; then target=/data/adb/openar; defport=80; defifaces="usb0 swlan0"; else target=/data/local/tmp/openar; defport=8080; defifaces="lo"; fi
[ -n "$port" ] || port=$defport
[ -n "$ifaces" ] || ifaces=$defifaces

out=$(sh "$here/tools/build_tree.sh" "$pack")
# adb is a Windows binary under Git Bash: hand it a Windows path (cygpath -m) when available.
out_adb=$out
if command -v cygpath >/dev/null 2>&1; then out_adb=$(cygpath -m "$out"); fi
echo "deploy: pack=$pack mode=$mode target=$target port=$port ifaces=$ifaces"
adb -s "$serial" shell "rm -rf $target.tmp; mkdir -p $target.tmp"
adb -s "$serial" push "$out_adb/." "$target.tmp/" >/dev/null
adb -s "$serial" shell "cd $target.tmp || exit 1
for f in etc/httpd.conf etc/commands etc/web.conf; do [ -f $target/\$f ] && cp -a $target/\$f \$f; done
if [ -d $target/var ]; then rm -rf var; cp -a $target/var .; fi
chmod 755 bin/* 2>/dev/null
chmod 755 etc/www/cgi-bin/*/*.cgi 2>/dev/null
[ -f etc/httpd.conf ] || { cp etc/httpd.conf.example etc/httpd.conf; echo 'openar: created etc/httpd.conf from the example -- change the password'; }
chmod 600 etc/httpd.conf
[ -f etc/web.conf ] || printf 'ifaces=\"%s\"\nport=%s\n' '$ifaces' '$port' > etc/web.conf
for p in /data/adb/magisk/busybox /data/local/tmp/busybox /system/bin/busybox; do
    if [ -x \$p ] && [ ! -x bin/busybox ]; then cp \$p bin/busybox; echo \"openar: busybox from \$p\"; break; fi
done
[ -x bin/busybox ] || echo 'openar: WARNING no busybox found on the device; put one at bin/busybox'"
adb -s "$serial" shell "rm -rf $target.old; if [ -d $target ]; then mv $target $target.old; fi; mv $target.tmp $target; rm -rf $target.old"

echo
echo "next:"
echo "  adb -s $serial shell $target/bin/openar-web start"
if [ "$mode" = root ]; then
    echo "  open http://<usb0 IP>/   (credentials in $target/etc/httpd.conf)"
else
    echo "  adb -s $serial forward tcp:8080 tcp:$port"
    echo "  open http://127.0.0.1:8080/"
fi
