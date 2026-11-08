#!/system/bin/sh
# openar web UI: one HTML fragment (no page frame), fetched by openar.js.
#   ?b=<name>  a status block: a file in etc/status.d (name filtered to [a-z0-9-], then checked)
#   ?c=<id>    an "auto" command from etc/commands(.default), printed as one section
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
qs() { print -nr -- "${QUERY_STRING:-}" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1 | tr -cd 'a-z0-9_-'; }
print -nr -- "Content-Type: text/html; charset=utf-8$CRLF""Cache-Control: no-store$CRLF$CRLF"
b=$(qs b); c=$(qs c)
if [ -n "$b" ] && [ -f "$OPENAR_ROOT/etc/status.d/$b" ]; then
    . "$OPENAR_ROOT/etc/status.d/$b" 2>&1
elif [ -n "$c" ]; then
    . "$OPENAR_ROOT/lib/openar-commands.sh"
    if cmd_get "$c" && [ "$c_group" = auto ]; then
        cmd_run "$c" view
        section_begin "$(print -nr -- "$c_desc" | esc)"
        [ "$r_rc" = 0 ] || alert warning "exit $r_rc" "$(print -nr -- "$r_err" | esc)"
        echo "<pre>$(print -r -- "$r_out" | esc)</pre>"
        section_end
    else
        alert error "No such auto command" "$(print -nr -- "$c" | esc)"
    fi
else
    alert error "No block" "$(print -nr -- "$b$c" | esc)"
fi
