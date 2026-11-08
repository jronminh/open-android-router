#!/system/bin/sh
# openar web UI: commands page -- the "settings app" of a headless box.
# The list comes from etc/commands (owner copy) else etc/commands.default; the web never edits it.
# One tab per "section":
#   auto commands -> placeholders filled in parallel by openar.js from block.cgi?c=<id>
#   view commands -> GET to this page, read-only
#   act commands  -> POST to act/run.cgi (confirmation, CSRF checks, log)
# A parameter regex of the form ^(a|b|c)$ is drawn as a <select>.
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
. "$OPENAR_ROOT/lib/openar-commands.sh"

qs_raw() { print -nr -- "${QUERY_STRING:-}" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1; }
urldecode() { "$OPENAR_BUSYBOX_PATH" httpd -d "$(print -nr -- "$1" | tr '+' ' ')"; }
OPENAR_BUSYBOX_PATH=$(openar_busybox)

page_head "Commands"
tab=$(qs_raw tab | tr -cd '0-9'); [ -n "$tab" ] || tab=1
sections=$(cmd_list | awk -F'\t' '!seen[$2]++ { print $2 }')
[ -n "$sections" ] || { alert error "No command list" "expected etc/commands or etc/commands.default"; page_foot; exit 0; }
cur=$(print -r -- "$sections" | sed -n "${tab}p")
[ -n "$cur" ] || { tab=1; cur=$(print -r -- "$sections" | sed -n 1p); }

set --
while IFS= read -r s; do [ -n "$s" ] && set -- "$@" "$s"; done <<EOF
$sections
EOF
tabmenu "$tab" "$@"

id=$(qs_raw id | tr -cd 'a-z0-9_-')
if [ -n "$id" ]; then
    arg=$(urldecode "$(qs_raw arg)")
    cmd_run "$id" view "$arg"; s=$?
    if [ $s = 2 ]; then
        alert error "Not run" "$(print -nr -- "$r_err" | esc)"
    else
        k=success; [ "$r_rc" = 0 ] || k=warning
        section_begin "$(print -nr -- "$c_desc" | esc)"
        alert "$k" "exit $r_rc" "<code>$(print -nr -- "$r_cmdline" | esc)</code>"
        echo "<pre>$(print -r -- "$r_out" | esc)</pre>"
        [ -n "$r_err" ] && echo "<h4>stderr</h4><pre>$(print -r -- "$r_err" | esc)</pre>"
        section_end
    fi
fi

# The whole tab in one awk process: every process start costs 25-50 ms on a phone.
cmd_list | awk -F'\t' -v sec="$cur" -v tab="$tab" '
function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
function param(re,   inner, n, i, opts, out) {
    if (re == "-") return ""
    if (re ~ /^\^\([A-Za-z0-9_.-]+(\|[A-Za-z0-9_.-]+)+\)\$$/) {
        inner = substr(re, 3, length(re) - 4); n = split(inner, opts, "|")
        out = "<select class=\"cbi-input-select\" name=\"arg\">"
        for (i = 1; i <= n; i++) out = out "<option>" opts[i] "</option>"
        return out "</select> "
    }
    return "<input class=\"cbi-input-text\" name=\"arg\" size=\"22\" placeholder=\"" esc(re) "\"> "
}
$2 != sec { next }
$3 == "auto" { auto = auto "<div class=\"cbi-section\" data-cmd=\"" $1 "\"><h3>" esc($7) "</h3><p class=\"spinning\">Loading…</p></div>\n"; next }
{
    id = $1; p = param($6)
    if ($3 == "view") {
        if ($6 == "-") f = "<a class=\"btn cbi-button-action\" href=\"?tab=" tab "&amp;id=" id "\">run</a>"
        else f = "<form class=\"inline\" method=\"get\"><input type=\"hidden\" name=\"tab\" value=\"" tab "\"><input type=\"hidden\" name=\"id\" value=\"" id "\">" p "<button class=\"btn cbi-button-action\">run</button></form>"
    } else {
        f = "<form class=\"inline\" method=\"post\" action=\"/cgi-bin/act/run.cgi\"><input type=\"hidden\" name=\"k\" value=\"cmd\"><input type=\"hidden\" name=\"id\" value=\"" id "\">" p "<button class=\"btn cbi-button-negative\">run</button></form>"
    }
    rows = rows "<tr class=\"tr\"><td class=\"td left\" width=\"40%\">" esc($7) "<br><small><code>" id "</code></small></td><td class=\"td left\">" f "</td></tr>\n"
}
END {
    printf "%s", auto
    if (rows != "") printf "<div class=\"cbi-section\"><h3>Actions</h3><table class=\"table\">\n%s</table></div>\n", rows
}'
echo "<p><small>Source: <code>$(print -nr -- "$CMDS" | esc)</code> -- edit it with <code>vi</code> over ADB; the web cannot change it. Red buttons change device state: two-step confirmation, logged.</small></p>"
page_foot
