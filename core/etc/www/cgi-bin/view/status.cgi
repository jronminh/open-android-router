#!/system/bin/sh
# openar web UI: status page, one section per file in etc/status.d (its first line is
# "# title: ..."). The frame is sent at once, then openar.js fetches each block in parallel
# from block.cgi?b=<file>, the way LuCI renders a spinner and fills it from RPC.
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
page_head "Status"
tab=$(tab_current)
list=$(grep -H '^# title:' "$OPENAR_ROOT"/etc/status.d/* 2>/dev/null)
set -- "Overview"
while IFS= read -r line; do [ -n "$line" ] && set -- "$@" "${line#*# title: }"; done <<EOF
$list
EOF
[ "$tab" -le $# ] 2>/dev/null || tab=1
tabmenu "$tab" "$@"
n=1
while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1)); f=${line%%:# title:*}
    [ "$tab" = 1 ] || [ "$tab" = "$n" ] || continue
    placeholder data-block "${f##*/}" "${line#*# title: }"
done <<EOF
$list
EOF
echo '<noscript><p>This page needs JavaScript to load the blocks.</p></noscript>'
page_foot
