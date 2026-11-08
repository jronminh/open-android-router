#!/system/bin/sh
# openar web UI: the act zone -- the only place the web changes device state.
#   POST only; Host must be one of the IPs (or published names) this tree serves, Origin/Referer
#   must point at that host; the target needs a second POST with confirm=yes; every run is logged.
#   Targets: k=cmd (command of group act), k=svc (service act verb), k=sms (send one SMS).
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
. "$OPENAR_ROOT/lib/openar-commands.sh"
openar_conf
BB=$(openar_busybox)
ACT_VERBS="apply airplane-toggle disable"

deny() { page_head "Denied"; alert error "Denied" "$(print -nr -- "$1" | esc)"; page_foot; exit 0; }
host_of() { print -nr -- "$1" | sed -E 's#^[a-z]+://##; s#[/:].*$##'; }

[ "${REQUEST_METHOD:-}" = POST ] || deny "POST only"
h=$(host_of "${HTTP_HOST:-}")
mine=0
for i in $OPENAR_IFACES; do
    a=$(oip "$i")
    [ -n "$h" ] && [ -n "$a" ] && [ "$h" = "$a" ] && mine=1
done
# ... or one of the names this phone publishes (etc/web.conf names=, served by the tether DNS).
# Still safe against DNS rebinding: a rebinding page carries the attacker's own name as Host.
for n in $OPENAR_NAMES; do [ -n "$h" ] && [ "$h" = "$n" ] && mine=1; done
[ $mine = 1 ] || deny "Host is not one of this device's addresses"
src=${HTTP_ORIGIN:-${HTTP_REFERER:-}}
[ -n "$src" ] || deny "missing Origin/Referer"
[ "$(host_of "$src")" = "$h" ] || deny "request came from another page ($(host_of "$src"))"

body=$(head -c "${CONTENT_LENGTH:-0}")
field() { print -nr -- "$body" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1; }
dec() { [ -n "$BB" ] && "$BB" httpd -d "$(print -nr -- "$1" | tr '+' ' ')" || print -nr -- "$1"; }
k=$(field k | tr -cd 'a-z'); confirm=$(field confirm | tr -cd 'a-z')
case "$k" in
    cmd)
        id=$(field id | tr -cd 'a-z0-9_-'); arg=$(dec "$(field arg)")
        cmd_get "$id" || deny "no such command: $id"
        [ "$c_group" = act ] || deny "command $id is not in the act group"
        label="command $id${arg:+ $arg}"
        hidden="<input type=\"hidden\" name=\"k\" value=\"cmd\"><input type=\"hidden\" name=\"id\" value=\"$id\"><input type=\"hidden\" name=\"arg\" value=\"$(print -nr -- "$arg" | esc | sed 's/"/\&quot;/g')\">" ;;
    svc)
        s=$(field s | tr -cd 'a-z0-9-'); v=$(field v | tr -cd 'a-z0-9-')
        case " $ACT_VERBS " in *" $v "*) ;; *) deny "verb '$v' is not allowed from the web" ;; esac
        [ -x "$OPENAR_ROOT/bin/openar-$s" ] || deny "no such service: $s"
        case " $("$OPENAR_ROOT/bin/openar-$s" verbs 2>/dev/null) " in *" $v "*) ;; *) deny "openar-$s has no verb '$v'" ;; esac
        label="openar-$s $v"
        hidden="<input type=\"hidden\" name=\"k\" value=\"svc\"><input type=\"hidden\" name=\"s\" value=\"$s\"><input type=\"hidden\" name=\"v\" value=\"$v\">" ;;
    sms)
        to=$(dec "$(field to)" | tr -cd '0-9+'); text=$(dec "$(field text)")
        [ -n "$to" ] && [ -n "$text" ] || deny "missing destination or text"
        label="SMS to $to (${#text} chars)"
        qt=$(print -nr -- "$text" | esc)
        hidden="<input type=\"hidden\" name=\"k\" value=\"sms\"><input type=\"hidden\" name=\"to\" value=\"$to\"><textarea name=\"text\" hidden>$qt</textarea><pre>$qt</pre>" ;;
    *) deny "missing target (k=cmd|svc|sms)" ;;
esac

if [ "$confirm" != yes ]; then
    page_head "Confirm"
    section_begin "Confirm"
    alert warning "Run $(print -nr -- "$label" | esc)?" "This changes device state and is logged."
    echo "<div class=\"cbi-page-actions\"><form class=\"inline\" method=\"post\" action=\"/cgi-bin/act/run.cgi\">$hidden<input type=\"hidden\" name=\"confirm\" value=\"yes\"><button class=\"btn cbi-button-negative\">Run</button></form> <a class=\"btn\" href=\"javascript:history.back()\">Cancel</a></div>"
    section_end
    page_foot; exit 0
fi

page_head "Result"
section_begin "Result"
st=0
case "$k" in
    cmd)
        cmd_run "$id" act "$arg"; st=$?
        out=$r_out; err=$r_err; rc=$r_rc ;;
    svc)
        out=$("$OPENAR_ROOT/bin/openar-$s" "$v" 2>&1); rc=$?
        echo "$(date '+%F %T') run openar-$s $v exit=$rc by=${REMOTE_USER:-?} from=${REMOTE_ADDR:-?}" >> "$OPENAR_ROOT/var/log/actions.log"
        olog "run openar-$s $v exit=$rc" ;;
    sms)
        out=$("$OPENAR_ROOT/bin/openar-sms" send "$to" "$text" 2>&1); rc=$? ;;
esac
if [ "$st" = 2 ]; then
    alert error "Not run" "$(print -nr -- "$r_err" | esc)"
else
    kind=success; [ "$rc" = 0 ] || kind=warning
    alert "$kind" "$(print -nr -- "$label" | esc) · exit $rc" "Logged to var/log/actions.log."
    echo "<pre>$(print -r -- "$out" | esc)</pre>"
    [ -n "${err:-}" ] && echo "<h4>stderr</h4><pre>$(print -r -- "$err" | esc)</pre>"
fi
section_end
page_foot
