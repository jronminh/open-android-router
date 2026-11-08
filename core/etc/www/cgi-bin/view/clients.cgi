#!/system/bin/sh
# openar web UI: clients page -- the neighbour table (ARP/ND) of this device.
# Android does not export the tether DHCP leases to a shell command, so this shows what the kernel
# knows: address, interface, MAC and state, one row per neighbour.
OPENAR_ROOT=${OPENAR_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}
. "$OPENAR_ROOT/bin/openar-web-lib"
page_head "Clients"
section_begin "Neighbours (ARP / ND)"
out=$(ip neigh 2>/dev/null)
echo '<table class="table">'
echo '<tr class="tr table-titles"><th class="th">Address</th><th class="th">Interface</th><th class="th">MAC</th><th class="th">State</th></tr>'
print -r -- "$out" | awk '
{
    ip = $1; iface = ""; mac = "-"; state = $NF
    for (i = 2; i <= NF; i++) {
        if ($i == "dev") iface = $(i + 1)
        else if ($i == "lladdr") mac = $(i + 1)
    }
    if (ip == "" || iface == "lo") next
    printf "<tr class=\"tr\"><td class=\"td left\"><code>%s</code></td><td class=\"td left\">%s</td><td class=\"td left\">%s</td><td class=\"td left\">%s</td></tr>\n", ip, iface, mac, state
    n++
}
END { if (n == 0) print "<tr class=\"tr\"><td class=\"td left\" colspan=\"4\"><i>(no neighbours yet)</i></td></tr>" }'
echo '</table>'
echo '<p><small>Source: <code>ip neigh</code>. The tether DHCP lease file is not exported by Android; a client appears after its first packet. IPv6 neighbours are listed too.</small></p>'
section_end
page_foot
