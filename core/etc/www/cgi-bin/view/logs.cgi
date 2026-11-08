#!/system/bin/sh
# openar web UI: logs page (read-only). One tab per source; only the open tab is read.
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
page_head "Logs"
tab=$(tab_current)
set -- "Actions" "Web" "openar" "Crash"
[ "$tab" -le $# ] 2>/dev/null || tab=1
tabmenu "$tab" "$@"
case "$tab" in
    1) t="var/log/actions.log (every action run)"; out=$(tail -n 100 "$OPENAR_ROOT/var/log/actions.log" 2>/dev/null) ;;
    2) t="var/log/web.log (httpd supervisor)"; out=$(tail -n 100 "$OPENAR_ROOT/var/log/web.log" 2>/dev/null) ;;
    3) t="var/log/openar.log (commands and services)"; out=$(tail -n 100 "$OPENAR_ROOT/var/log/openar.log" 2>/dev/null) ;;
    4) t="logcat -b crash"; out=$(logcat -d -b crash 2>/dev/null | tail -60) ;;
esac
section_begin "$t"
echo "<pre>$(print -r -- "${out:-(empty)}" | esc)</pre>"
section_end
page_foot
