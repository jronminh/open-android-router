#!/system/bin/sh
# openar-sms.sh -- SMS over Android's own content provider (read) and the isms binder (send).
# Read: "content query --uri content://sms/<box>" -- no app, no database file access.
# Send: ISms.sendTextForSubscriber = transaction 5 (AOSP android15 ISms.aidl and this tree's
# reference); subId from ISms.getPreferredSmsSubscription = transaction 20. Running uid matters:
# com.android.shell (uid 2000) holds SEND_SMS, so a root-mode web process drops to 2000 with Magisk
# su; a rootless process already is 2000 and calls the binder directly.
# One part only: 160 ASCII characters, or 70 when the text has non-ASCII (UCS-2).
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}

# sms_raw <inbox|sent|all> <N>: newest first. "content" exits 0 even when the provider is missing
# (it prints the error on stderr), so the output is checked: no provider -> 3 and the text on stderr.
sms_raw() {
    case "$1" in inbox|sent) u=content://sms/$1 ;; *) u=content://sms ;; esac
    out=$(content query --uri "$u" --projection _id:type:address:date:read:body --sort "date DESC LIMIT $2" 2>&1)
    rc=$?
    case "$out" in
        *"Error while accessing provider"*|*"Could not find provider"*)
            print -r -- "$out" >&2; return 3 ;;
    esac
    print -r -- "$out"
    return $rc
}

# sms_send <to> <text>: echoes the binder reply; 0 = accepted, 2 = bad input, 3 = shortcode refused,
# 1 = binder error. Short numbers (1-5 digits) are refused: Android shows a premium-SMS confirmation
# dialog on the screen and the message hangs there (measured on S21, 2026-11-08).
sms_send() {
    to=$1; text=$2
    print -nr -- "$to" | grep -Eqx '[0-9+]{3,15}' || { echo "invalid destination (3-15 digits, optional +)"; return 2; }
    [ -n "$text" ] || { echo "empty text"; return 2; }
    digits=${to#+}
    case "$digits" in
        [0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9])
            echo "shortcode $to refused: Android may show a premium-SMS confirmation dialog; allow it first (docs/SUPPORT.md)"; return 3 ;;
    esac
    max=160; print -nr -- "$text" | LC_ALL=C grep -q '[^ -~]' && max=70
    len=$(print -nr -- "$text" | wc -m)
    [ "$len" -le "$max" ] || { echo "text is $len chars, one part allows $max (70 with non-ASCII)"; return 2; }
    sub=$(service call isms 20 2>/dev/null | sed -n 's/.*Parcel([[:space:]]*00000000 \([0-9a-f]\{8\}\).*/\1/p')
    sub=$(( 0x${sub:-1} ))
    if [ "$(id -u)" = 0 ]; then
        # root web process: drop to uid 2000 (com.android.shell holds SEND_SMS). The text is one
        # single-quoted word inside the su command string; inner single quotes are escaped.
        q=$(print -nr -- "$text" | sed "s/'/'\\\\''/g")
        cmd="service call isms 5 i32 $sub s16 com.android.shell i32 -1 s16 '$to' i32 -1 s16 '$q' i32 0 i32 0 i32 1 i64 0"
        out=$(su 2000 -c "$cmd" 2>&1)
    else
        # rootless: already uid 2000. Pass the text as ONE argv element -- no shell re-parsing,
        # so spaces, quotes, $ and backticks in the message are data, not code.
        out=$(service call isms 5 i32 "$sub" s16 com.android.shell i32 -1 s16 "$to" i32 -1 s16 "$text" i32 0 i32 0 i32 1 i64 0 2>&1)
    fi
    echo "subId=$sub $out"
    print -r -- "$out" | grep -Eq "Parcel\([[:space:]]*00000000[[:space:]]+'\.\.\.\.'\)" && return 0
    return 1
}

# TZ offset of the phone in seconds (date +%z = +0700) for the awk date conversion.
sms_tzoff() {
    z=$(date +%z); s=1; case "$z" in -*) s=-1 ;; esac; z=${z#[+-]}
    echo $(( s * (${z%??} * 3600 + ${z#??} * 60) ))
}

# SMS_AWK: sms_raw output -> records; mode=text|html; tz=<offset s>.
SMS_AWK='
function civil(t,   z, era, doe, yoe, y, doy, mp, d, m, s) {
    s = t % 86400; z = int(t / 86400) + 719468
    era = int(z / 146097); doe = z - era * 146097
    yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
    y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
    mp = int((5 * doy + 2) / 153); d = doy - int((153 * mp + 2) / 5) + 1
    m = (mp < 10) ? mp + 3 : mp - 9; if (m <= 2) y++
    return sprintf("%04d-%02d-%02d %02d:%02d", y, m, d, int(s / 3600), int(s % 3600 / 60))
}
function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
function field(k,   r) { if (match(rec, k "=[^,]*")) { r = substr(rec, RSTART + length(k) + 1, RLENGTH - length(k) - 1); return r } return "" }
function flush(   id, ty, ad, dt, rd, when, dir) {
    if (rec == "") return
    id = field("_id"); ty = field("type"); ad = field("address"); dt = field("date"); rd = field("read")
    when = civil(int(dt / 1000) + tz); dir = (ty == "2") ? "->" : "<-"
    if (mode == "html") {
        printf "<tr class=\"tr\"><td class=\"td left\" width=\"22%%\"><b>%s</b><br><small>%s %s%s</small></td><td class=\"td left\"><pre style=\"white-space:pre-wrap\">%s</pre></td></tr>\n", esc(ad), dir, when, (rd == "0" ? " &middot; <b>new</b>" : ""), esc(body)
    } else {
        printf "#%s %s %s %s%s\n%s\n\n", id, dir, when, ad, (rd == "0" ? " [new]" : ""), body
    }
    n++; rec = ""; body = ""
}
/^Row: [0-9]+ / { flush(); rec = $0; i = index($0, ", body="); body = (i ? substr($0, i + 7) : ""); next }
{ body = body "\n" $0 }
END { flush(); if (mode == "html" && n == 0) print "<tr class=\"tr\"><td class=\"td left\"><i>(no messages)</i></td></tr>" }
'
