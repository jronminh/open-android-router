#!/system/bin/sh
# probe-busybox.sh [busybox] -- check the applets and the option behaviour the shims rely on.
#
# Run it on the device (this is a device-side script, not a host tool):
#   adb push tools/probe-busybox.sh /data/local/tmp/
#   adb shell sh /data/local/tmp/probe-busybox.sh /data/local/tmp/openar/bin/busybox
#
# Every line that prints a non-zero rc or no output marks an applet that a shim depends on but
# this busybox does not provide (deploy.sh already warns about missing applets; this goes one
# step further and checks the options the tree actually uses).
set -u
BB=${1:-/data/local/tmp/openar/bin/busybox}
[ -x "$BB" ] || { echo "probe-busybox: no executable busybox at $BB" >&2; exit 1; }
echo "busybox: $BB ($("$BB" | head -n 1))"
echo "sleep:"; "$BB" sleep 0.5; echo "rc=$?"
echo "printf-tab:"; "$BB" printf 'a\tb\n' | od -An -c | head -1
echo "egrep:"; echo x | "$BB" egrep x; echo "rc=$?"
echo "date:"; "$BB" date +%s
echo "timeout:"; "$BB" timeout 1 sleep 5; echo "rc=$?"
echo "mktemp:"; T=$("$BB" mktemp /data/local/tmp/t.XXXXXX); echo "$T rc=$?"; rm -f "$T"
echo "sed -E:"; echo http://x | "$BB" sed -E 's#^[a-z]+://##'
echo "grep -Eqx:"; echo enable | "$BB" grep -Eqx '^(enable|disable)$'; echo "rc=$?"
