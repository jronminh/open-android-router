#!/system/bin/sh
# openar web UI: SMS page. Tabs: inbox, sent, compose. Reading uses Android's SMS content provider
# (lib/openar-sms.sh, the same as "openar-sms list" over ADB); sending is a POST to the act zone
# (confirmation, CSRF checks, log). One part per message; shortcodes are refused by the library.
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
. "$OPENAR_ROOT/lib/openar-sms.sh"
page_head "SMS"
tab=$(tab_current)
set -- "Inbox" "Sent" "Compose"
[ "$tab" -le $# ] 2>/dev/null || tab=1
tabmenu "$tab" "$@"
case "$tab" in
    1|2)
        box=inbox; [ "$tab" = 2 ] && box=sent
        section_begin "Newest 50 messages"
        raw=$(sms_raw "$box" 50 2>&1); rc=$?
        if [ $rc != 0 ]; then
            alert error "Cannot read SMS" "$(print -r -- "$raw" | esc)"
        else
            echo '<table class="table">'
            print -r -- "$raw" | awk -v mode=html -v tz="$(sms_tzoff)" "$SMS_AWK"
            echo '</table>'
        fi
        echo "<p><small>Over ADB: <code>openar-sms list $box 50</code></small></p>"
        section_end ;;
    3)
        section_begin "Compose"
        echo '<form method="post" action="/cgi-bin/act/run.cgi"><input type="hidden" name="k" value="sms">'
        echo '<div class="cbi-value"><label class="cbi-value-title">Destination</label><div class="cbi-value-field"><input class="cbi-input-text" name="to" size="20" placeholder="e.g. 0912345678"></div></div>'
        echo '<div class="cbi-value"><label class="cbi-value-title">Text</label><div class="cbi-value-field"><textarea class="cbi-input-textarea" name="text" rows="4" cols="40" maxlength="640"></textarea></div></div>'
        echo '<div class="cbi-page-actions"><button class="btn cbi-button-negative">Send</button></div></form>'
        alert notice "One part only" "160 ASCII characters, or 70 with non-ASCII. Shortcodes (1-5 digits) are refused: Android shows a premium-SMS confirmation dialog for them."
        section_end ;;
esac
page_foot
