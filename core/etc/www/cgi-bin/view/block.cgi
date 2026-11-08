#!/system/bin/sh
# openar web UI: one HTML fragment (no page frame), fetched by openar.js.
#   ?b=<name>  a status block: a file in etc/status.d (name filtered to [a-z0-9-], then checked)
#   ?c=<id>    an "auto" command from etc/commands(.default), printed as one section
#   ?s=&v=     a read-only verb (status|check) of a service in bin/openar-<name>
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
qs() { print -nr -- "${QUERY_STRING:-}" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1 | tr -cd 'a-z0-9_-'; }
print -nr -- "Content-Type: text/html; charset=utf-8$CRLF""Cache-Control: no-store$CRLF$CRLF"
b=$(qs b); c=$(qs c); s=$(qs s); v=$(qs v)
if [ -n "$b" ] && [ -f "$OPENAR_ROOT/etc/status.d/$b" ]; then
    . "$OPENAR_ROOT/etc/status.d/$b" 2>&1
elif [ -n "$s" ]; then
    # read-only service verbs only, and only when the service declares them
    vs=$(grep -m1 '^VERBS=' "$OPENAR_ROOT/bin/openar-$s" 2>/dev/null)
    vs=${vs#*VERBS=\"}; vs=${vs%%\"*}
    ok=0
    case " status check " in *" $v "*) ok=1 ;; esac
    case " $vs " in *" $v "*) ;; *) ok=0 ;; esac
    if [ "$ok" = 1 ] && [ -x "$OPENAR_ROOT/bin/openar-$s" ]; then
        out=$("$OPENAR_ROOT/bin/openar-$s" "$v" 2>&1); rc=$?
        section_begin "openar-$s $v"
        if [ "$rc" = 0 ]; then
            [ "$v" = check ] && alert success "In line with intent" "check exit 0"
        else
            alert warning "exit $rc" "$( [ "$v" = check ] && echo 'Differs from intent -- see below.' || echo 'Error -- see below.')"
        fi
        [ -n "$out" ] && echo "<pre>$(print -r -- "$out" | esc)</pre>"
        section_end
    else
        alert error "Not allowed" "$(print -nr -- "openar-$s $v" | esc)"
    fi
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
