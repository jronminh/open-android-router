# Ideas (recorded, not planned)

The scope of this repository is deliberately small: **expose the network capabilities a device
already has, through an OpenWrt-shaped management layer**. Everything below was investigated and is
recorded so it is not re-litigated; none of it is on the roadmap. Re-open only with a concrete
device need and a check that passes on the three test devices.

| idea | why it stays out |
|---|---|
| Port `uhttpd`/`ubus`/`rpcd` (as a static-musl island) | Duplicates what busybox httpd + shell already does; only pays off for a full LuCI, which is out of scope |
| Port `procd` | It is an init; Android's init owns PID 1 |
| Package compatibility (`opkg`/`.ipk`) | OpenWrt packages assume `/etc/init.d`, uci, procd, absolute paths; no cross-libc `.so` |
| Full LuCI / `luci-app-*` (ucode + JS + ubus) | Needs the whole RPC stack; the theme and the block/tab patterns were the useful part and are already used |
| A plugin feed / runtime installer with signatures | A plugin is shell code running as shell/root; installation stays owner-initiated over ADB |
| libc "island" (ship musl loader + runtime; dynamic musl/Foreign binaries) | Static musl payloads already run; dynamic needs a loader wrapper. A general shim (ptrace-like) is a separate research project (`deb-native`-scale) |
| Running unmodified OpenWrt plugins | Blocked by absolute paths, PID 1, UI stack, not by musl itself (see LIBC.md) |
| L0-L2 tree alignment (`www/`, `etc/init.d`, `menu.d`, uci) | Only worth it if plugins are actively ported; today naming alone buys little |

## If one is ever picked up

1. State the device capability it unlocks, not the component it ports.
2. It must keep the rootless floor and pass `tools/check.sh` on Sharp, S10 and S21.
3. Add a line to docs/SUPPORT.md and a row above with the date, or drop it.
