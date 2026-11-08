#!/bin/sh
# check.sh <serial> [--mode root|shell] [--user admin] [--pass admin] [--port N] [--forward 18080]
#
# The floor check: a device must serve the pages and run a command with nothing but adb.
#   shell mode: adb forward + curl on the host (the tree serves loopback).
#   root mode:  the tree serves a LAN IP, which adb forward cannot reach; the check runs
#               busybox wget on the device itself, with an Authorization header.
# Exit 0 only when every check passes.
set -eu
[ -n "${MSYSTEM:-}" ] && export MSYS_NO_PATHCONV=1
serial=${1:-}; shift || true
[ -n "$serial" ] || { echo "usage: check.sh <serial> [--mode root|shell] [--user u] [--pass p] [--port N] [--forward N]" >&2; exit 64; }
mode="" user=admin pass=admin port="" forward=18080
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) mode=$2; shift ;;
        --user) user=$2; shift ;;
        --pass) pass=$2; shift ;;
        --port) port=$2; shift ;;
        --forward) forward=$2; shift ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done
uid=$(adb -s "$serial" shell id -u | tr -d '\r')
[ -n "$mode" ] || { if [ "$uid" = 0 ]; then mode=root; else mode=shell; fi; }
if [ "$mode" = root ]; then target=/data/adb/openar; defport=80; else target=/data/local/tmp/openar; defport=8080; fi
[ -n "$port" ] || port=$defport
conf_get() {  # conf_get <key>: value from the device's etc/web.conf
    if [ "$mode" = root ]; then
        adb -s "$serial" shell "su -c 'sed -n \"s/^$1=//p\" $target/etc/web.conf'" 2>/dev/null
    else
        adb -s "$serial" shell "sed -n 's/^$1=//p' $target/etc/web.conf" 2>/dev/null
    fi | tr -d '\r"' | head -1
}
p=$(conf_get port); [ -n "$p" ] && port=$p
fails=0
say() { printf '%-30s %s\n' "$1" "$2"; }
say "device" "$serial (uid $uid, mode $mode, $target, port $port)"

# busybox-first: the shims are the portability contract; without them the tree is not supported.
shim_missing=""
for a in sed awk ip timeout; do
    if [ "$mode" = root ]; then
        adb -s "$serial" shell "su -c 'test -x $target/bin/shims/$a'" 2>/dev/null || shim_missing="$shim_missing $a"
    else
        adb -s "$serial" shell "test -x $target/bin/shims/$a" 2>/dev/null || shim_missing="$shim_missing $a"
    fi
done
if [ -n "$shim_missing" ]; then say "busybox shims" "FAIL ($shim_missing)"; fails=$((fails + 1)); else say "busybox shims" "PASS"; fi

if [ "$mode" = shell ]; then
    adb -s "$serial" forward --remove tcp:$forward >/dev/null 2>&1 || true
    adb -s "$serial" forward tcp:$forward tcp:$port >/dev/null
    base="http://127.0.0.1:$forward"
    sleep 1
    page() {
        i=0
        while [ $i -lt 4 ]; do
            if curl -s -f -u "$user:$pass" "$base$2" >/dev/null 2>&1; then say "$1" "PASS"; return 0; fi
            i=$((i + 1)); sleep 1
        done
        say "$1" "FAIL"; fails=$((fails + 1))
    }
    page "web root" "/"
    page "status.cgi" "/cgi-bin/view/status.cgi"
    page "commands.cgi" "/cgi-bin/view/commands.cgi"
    page "logs.cgi" "/cgi-bin/view/logs.cgi"
    body=""; i=0
    while [ $i -lt 4 ]; do
        body=$(curl -s -f -u "$user:$pass" "$base/cgi-bin/view/block.cgi?b=10-device" 2>/dev/null || true)
        case "$body" in *cbi-section*) break ;; esac
        i=$((i + 1)); sleep 1
    done
    adb -s "$serial" forward --remove tcp:$forward >/dev/null 2>&1 || true
else
    # root: connect to the address the server is bound to, from the device itself
    ifaces=$(conf_get ifaces)
    [ -n "$ifaces" ] || ifaces="usb0 swlan0"
    ip=""
    for i in $ifaces; do
        a=$(adb -s "$serial" shell "su -c 'ip -4 -o addr show $i'" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
        [ -n "$a" ] && { ip=$a; break; }
    done
    if [ -z "$ip" ]; then
        say "interface" "FAIL (no address on: $ifaces)"; fails=$((fails + 1))
    else
        say "interface" "$ip"
        BB=/data/adb/magisk/busybox
        b64=$(printf '%s' "$user:$pass" | base64 | tr -d '\r\n')
        hdr="Authorization: Basic $b64"
        page() {
            adb -s "$serial" shell "su -c '$BB wget -q -O /dev/null --header \"$hdr\" http://$ip:$port$2'" >/dev/null 2>&1 \
                && say "$1" "PASS" || { say "$1" "FAIL"; fails=$((fails + 1)); }
        }
        page "web root" "/"
        page "status.cgi" "/cgi-bin/view/status.cgi"
        page "commands.cgi" "/cgi-bin/view/commands.cgi"
        page "logs.cgi" "/cgi-bin/view/logs.cgi"
        body=$(adb -s "$serial" shell "su -c '$BB wget -q -O - --header \"$hdr\" http://$ip:$port/cgi-bin/view/block.cgi?b=10-device'" 2>/dev/null || true)
    fi
fi
case "$body" in *cbi-section*) say "status block" "PASS" ;; *) say "status block" "FAIL"; fails=$((fails + 1)) ;; esac
if [ "$mode" = root ]; then
    out=$(adb -s "$serial" shell "su -c 'sh $target/bin/openar-cmd run uptime'" 2>/dev/null | tr -d '\r')
else
    out=$(adb -s "$serial" shell "sh $target/bin/openar-cmd run uptime" 2>/dev/null | tr -d '\r')
fi
case "$out" in *load*) say "openar-cmd run uptime" "PASS" ;; *) say "openar-cmd run uptime" "FAIL ($out)"; fails=$((fails + 1)) ;; esac
if [ $fails = 0 ]; then echo "result: PASS"; exit 0; fi
echo "result: FAIL ($fails)"; exit 1
