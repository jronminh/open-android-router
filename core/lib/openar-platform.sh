#!/system/bin/sh
# openar-platform.sh -- the one place that answers "where am I running, and what may I do".
#
# Every entry script sets OPENAR_ROOT from its own location and sources this file:
#   bin/openar-*        OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
#   etc/www/cgi-bin/*   OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
#
# The rootless shell is the floor (docs/ARCHITECTURE.md): nothing here may assume root.
#
# Sets:
#   OPENAR_MODE     root | shell            (uid 0 or not)
#   OPENAR_IFACES   interfaces to serve     (etc/web.conf: ifaces="usb0 swlan0")
#   OPENAR_PORT     web port                (etc/web.conf: port=80)
#   OPENAR_LOG      log directory           (var/log)
#
# Helpers:
#   openar_conf              load etc/web.conf over the mode defaults
#   openar_busybox           path of a busybox with httpd, empty when none
#   olog <text>              append to var/log/openar.log, and to the kernel log when writable
#   oip <iface>              IPv4 address of an interface, empty when down

OPENAR_MODE=shell
[ "$(id -u 2>/dev/null)" = 0 ] && OPENAR_MODE=root
OPENAR_LOG=${OPENAR_LOG:-$OPENAR_ROOT/var/log}
mkdir -p "$OPENAR_LOG" "$OPENAR_ROOT/var/run" "$OPENAR_ROOT/tmp" 2>/dev/null

# POSIX tools come from busybox through bin/shims (created by tools/deploy.sh); the Android
# framework commands (getprop, settings, svc, pm, am, dumpsys, logcat) stay the system binaries.
# busybox-first removes the toybox question: applets and options differ between AOSP versions.
# ping is deliberately not shimmed -- busybox ping needs root, Android's ping does not.
OPENAR_SHIMS=$OPENAR_ROOT/bin/shims
PATH=$OPENAR_SHIMS:$OPENAR_ROOT/bin:/system/bin:/system/xbin
export PATH

# Kernel log only when the kernel lets us write it: rootless "echo > /dev/kmsg" is a hard error
# printed on stderr by the shell itself (measured on Sharp 701SH, 2026-11-08).
olog() {
    echo "$(date '+%F %T') ${0##*/}: $*" >> "$OPENAR_LOG/openar.log" 2>/dev/null
    [ -w /dev/kmsg ] && echo "openar: $*" > /dev/kmsg 2>/dev/null
    return 0
}

openar_busybox() {
    for p in "${OPENAR_BUSYBOX:-}" "$OPENAR_ROOT/bin/busybox" /data/adb/magisk/busybox /data/local/tmp/busybox; do
        [ -n "$p" ] && [ -x "$p" ] && { echo "$p"; return 0; }
    done
    command -v busybox 2>/dev/null
}

# Defaults: a rooted box serves the cable and the hotspot; a plain shell box serves loopback
# only (reach it with "adb forward"), which exposes nothing to the network until configured.
openar_conf() {
    ifaces=""; [ "$OPENAR_MODE" = root ] && ifaces="usb0 swlan0"
    [ "$OPENAR_MODE" = shell ] && ifaces="lo"
    port=80; [ "$OPENAR_MODE" = shell ] && port=8080
    [ -f "$OPENAR_ROOT/etc/web.conf" ] && . "$OPENAR_ROOT/etc/web.conf"
    OPENAR_IFACES=$ifaces
    OPENAR_PORT=$port
}

oip() {
    ip -4 -o addr show "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1
}
