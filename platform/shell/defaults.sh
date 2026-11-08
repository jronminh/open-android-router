# platform/shell/defaults.sh -- values for a plain, non-rooted device (the floor).
# Sourced by tools/deploy.sh when --shell is used. A shell tree serves loopback by default:
# nothing is exposed to a network until etc/web.conf says so.
OPENAR_IFACES="lo"
OPENAR_PORT=8080
OPENAR_BUSYBOX_SEARCH="/data/adb/magisk/busybox /data/local/tmp/busybox /system/bin/busybox"
