#!/system/bin/sh
# openar web UI: services page -- every bin/openar-<name> with a VERBS="..." line is a service.
# One tab per service. Read-only verbs (status, check) load by themselves through block.cgi?s=&v=;
# act verbs (apply, airplane-toggle) are POST buttons to the act zone; other verbs are ADB-only.
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
READONLY="status check"
ACT="apply airplane-toggle"

page_head "Services"
tab=$(tab_current)
list=$(grep -H '^VERBS=' "$OPENAR_ROOT"/bin/openar-* 2>/dev/null)
set --
while IFS= read -r line; do
    [ -n "$line" ] || continue
    f=${line%%:VERBS=*}; set -- "$@" "${f##*/openar-}"
done <<EOF
$list
EOF
[ "$tab" -le $# ] 2>/dev/null || tab=1
tabmenu "$tab" "$@"
eval "name=\${$tab}"
line=$(print -r -- "$list" | grep "/openar-$name:VERBS=")
vs=${line#*:VERBS=\"}; vs=${vs%%\"*}

for v in $READONLY; do
    case " $vs " in *" $v "*) placeholder data-svc "$name:$v" "openar-$name $v" ;; esac
done
section_begin "Actions"
echo "<p>Shell: <code>openar-$name</code> -- same verbs over ADB. Red buttons change device state (confirmation, logged).</p>"
print -nr -- '<div class="cbi-page-actions" style="text-align:left">'
any=0
for v in $vs; do
    case " $READONLY " in *" $v "*) continue ;; esac
    any=1
    case " $ACT " in
        *" $v "*) act_button "$v" negative k=svc s="$name" v="$v" ;;
        *) print -nr -- " <span class=\"btn\" disabled title=\"ADB only\">$v</span>" ;;
    esac
done
[ $any = 1 ] || print -nr -- '<i>This service has read-only verbs only.</i>'
echo '</div>'
section_end
page_foot
