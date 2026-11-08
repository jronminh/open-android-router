#!/bin/sh
# check.sh <serial> [--user admin] [--pass admin] [--port N] [--forward 18080]
#
# The floor check: a device must serve the pages and run a command with nothing but adb.
# Uses adb forward + curl on the host, so no network trust is needed.
# Exit 0 only when every check passes.
set -eu
serial=${1:-}; shift || true
[ -n "$serial" ] || { echo "usage: check.sh <serial> [--user u] [--pass p] [--port N] [--forward N]" >&2; exit 64; }
user=admin pass=admin port="" forward=18080
while [ $# -gt 0 ]; do
    case "$1" in
        --user) user=$2; shift ;;
        --pass) pass=$2; shift ;;
        --port) port=$2; shift ;;
        --forward) forward=$2; shift ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done
uid=$(adb -s "$serial" shell id -u | tr -d '\r')
if [ "$uid" = 0 ]; then target=/data/adb/openar; defport=80; else target=/data/local/tmp/openar; defport=8080; fi
[ -n "$port" ] || port=$defport
if adb -s "$serial" shell "[ -f $target/etc/web.conf ]" 2>/dev/null; then
    p=$(adb -s "$serial" shell "sed -n 's/^port=//p' $target/etc/web.conf" | tr -d '\r' | head -1)
    [ -n "$p" ] && port=$p
fi
fails=0
say() { printf '%-30s %s\n' "$1" "$2"; }
say "device" "$serial (uid $uid, $target, port $port)"
adb -s "$serial" forward --remove tcp:$forward >/dev/null 2>&1 || true
adb -s "$serial" forward tcp:$forward tcp:$port >/dev/null
base="http://127.0.0.1:$forward"
sleep 1   # the listener needs a moment before it accepts connections
page() {  # page <label> <path>
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
body=""
i=0
while [ $i -lt 4 ]; do
    body=$(curl -s -f -u "$user:$pass" "$base/cgi-bin/view/block.cgi?b=10-device" 2>/dev/null || true)
    case "$body" in *cbi-section*) break ;; esac
    i=$((i + 1)); sleep 1
done
case "$body" in *cbi-section*) say "status block" "PASS" ;; *) say "status block" "FAIL"; fails=$((fails + 1)) ;; esac
out=$(adb -s "$serial" shell "sh $target/bin/openar-cmd run uptime" 2>/dev/null | tr -d '\r')
case "$out" in *load*) say "openar-cmd run uptime" "PASS" ;; *) say "openar-cmd run uptime" "FAIL ($out)"; fails=$((fails + 1)) ;; esac
adb -s "$serial" forward --remove tcp:$forward >/dev/null 2>&1 || true
if [ $fails = 0 ]; then echo "result: PASS"; exit 0; fi
echo "result: FAIL ($fails)"; exit 1
