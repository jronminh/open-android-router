#!/system/bin/sh
BB=/data/local/tmp/busybox
echo "sleep:"; $BB sleep 0.5; echo "rc=$?"
echo "printf-tab:"; $BB printf 'a\tb\n' | od -An -c | head -1
echo "egrep:"; echo x | $BB egrep x; echo "rc=$?"
echo "date:"; $BB date +%s
echo "timeout:"; $BB timeout 1 sleep 5; echo "rc=$?"
echo "mktemp:"; T=$($BB mktemp /data/local/tmp/t.XXXXXX); echo "$T rc=$?"; rm -f "$T"
echo "sed -E:"; echo http://x | $BB sed -E 's#^[a-z]+://##'
echo "grep -Eqx:"; echo enable | $BB grep -Eqx '^(enable|disable)$'; echo "rc=$?"
