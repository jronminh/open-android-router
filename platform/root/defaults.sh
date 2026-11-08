# platform/root/defaults.sh -- values for a rooted device (Magisk or similar).
# Sourced by tools/deploy.sh when --root is used. Runtime detection stays in
# core/lib/openar-platform.sh; this file only decides the deployment defaults.
OPENAR_IFACES="usb0 swlan0"
OPENAR_PORT=80
OPENAR_BUSYBOX_SEARCH="/data/adb/magisk/busybox /system/bin/busybox"
