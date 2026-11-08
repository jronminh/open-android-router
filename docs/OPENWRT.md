# OpenWrt compatibility

> Research note, not a roadmap. The scope is device capabilities plus the OpenWrt-shaped
> management layer; the ideas here are recorded in [IDEAS.md](IDEAS.md), not planned.

The web UI, the command model and the service model were **modelled on OpenWrt** (LuCI Bootstrap
theme, busybox httpd, procd respawn policy, rc.common verb dispatch, luci-app-commands). This note
records what of OpenWrt can run **on Android as-is**, what needs a port, and what should not be
carried over. It was measured on a SHARP 701SH (Android 10, rootless) in 2026-11-08.

## What the tree borrowed from OpenWrt

| idea | our file | OpenWrt reference |
|---|---|---|
| web server per interface, respawn on death | `core/bin/openar-web` | procd `service/instance.c` (threshold 3600 s, retry 5, 5 s restart) |
| `status/check/apply/verbs` service dispatch | `core/lib/openar-service.sh` | `base-files/files/etc/rc.common` |
| command list, parameter handling, output cap | `core/lib/openar-commands.sh` | `luci-app-commands/ucode/controller/commands.uc` |
| page frame, tabs, blocks, spinner | `core/bin/openar-web-lib`, `openar.js` | LuCI Bootstrap theme + `luci-mod-status` block pattern |
| one password, whole site | `core/etc/httpd.conf` | `uhttpd/auth.c` (Basic) |

## Tested: shell layer works on Android

OpenWrt `rc.common` + `lib/functions.sh` + `lib/functions/service.sh` were copied to
`/data/local/tmp/owrt` and run under Android's `/system/bin/sh` (mksh):

```
IPKG_INSTROOT=/data/local/tmp/owrt sh rc.common sample start
START-OK
rc=0
```

`local` (used heavily by `functions.sh`) works in Android mksh. So a **non-procd** OpenWrt init
script can run on Android without modification, as long as it does not call the procd helpers.

## Verdict per component

| component | on Android | effort | notes |
|---|---|---|---|
| busybox httpd | **used today** | 0 | already the server (Magisk busybox) |
| LuCI Bootstrap assets | **used today** | 0 | CSS/logo are plain files (Apache-2.0) |
| `rc.common` (non-procd) | **works** | 0-1 h | tested; only paths/space differ |
| `uhttpd` | builds; not built yet | 1-2 days | C + libubox + json-c (ubus/ucode/lua/TLS optional). Basic auth and CGI env are compatible; replaces busybox httpd |
| `uci` CLI/lib | builds | 0.5-1 day | low value: our config is plain files in `etc/` |
| `jshn` + `procd.sh` helpers | needs ubus | 1 day + deps | pure shell on top of `ubus`; without ubus it fails at `_procd_ubus_call` |
| `ubus`/`ubusd` | builds | 2-3 days | unix sockets, root daemon; SELinux/magisk domain must allow it |
| `rpcd` (ACL, sessions, JSON-RPC) | builds after ubus+uci | 2-4 days | duplicates the act zone's job; only useful for a full LuCI |
| `procd` | **not viable** | - | designed to be PID 1; Android init owns PID 1. Use Magisk `service.d` / init services instead |
| full LuCI (ucode + luci-base + rpcd + ubus + uci) | needs the whole stack | weeks | `commands.uc` imports `luci.http`, `fs`, runs under ucode; no reason to carry it |
| `netifd` / `firewall4` | no | - | Android has netd/Connectivity; running them would fight the framework |

## What that means

- **"Runs on OpenWrt" is already true for the shell parts** (rc.common style dispatch); the C
  daemons are portable in principle but each needs a static musl build and a place to run under
  Android's SELinux, exactly like the dropbear experiment in the personal project.
- **procd is the hard stop.** It is an init, not a service manager; Android's init already plays
  that role. The respawn policy was re-implemented in `openar-web` for this reason.
- **Porting LuCI itself is not worth it.** The value of LuCI is its RPC/ubus/uci stack, and that
  stack is bigger than this whole tree. The theme and the block/tab patterns were the useful part.
- **The reverse direction is cheap.** `openar` was written to look like OpenWrt: replacing the
  ~60 `print -r` calls (mksh builtin) with `printf`, swapping the Android commands/blocks for
  `uci`/`ubus`/`iw` ones and the paths, is roughly a 1-2 day port to a real OpenWrt box.

## If a component is ever pulled in

1. Build static (musl) like `tools/get_busybox.sh` does not (that one copies); keep the build
   script and sha256 in `tools/`.
2. Give it a `platform/` entry and a line in `docs/SUPPORT.md`; a component that is not tested on
   the three devices is not supported.
3. Do not replace Android's own init/netd: OpenWrt's daemons may only fill gaps that Android
   framework does not already cover.
