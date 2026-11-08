# Plugins

> Research note, not a roadmap. The scope is device capabilities plus the OpenWrt-shaped
> management layer; the ideas here are recorded in [IDEAS.md](IDEAS.md), not planned.

OpenWrt's reputation comes from its plugin ecosystem more than from the base system. This note
checks what of that ecosystem can exist on Android, and what the smallest honest plugin model for
this tree is. Measured on a SHARP 701SH (Android 10, rootless) in 2026-11-08.

## The three plugin layers in OpenWrt

| layer | mechanism | reusable on Android? |
|---|---|---|
| **packages / feeds** | `opkg` + `.ipk` (tar + control scripts), feeds of prebuilt musl binaries, `/etc/init.d` scripts, uci config | **Not directly.** Paths assume `/etc/init.d`, `/usr/lib`, uci and procd. Static musl binaries do run (LIBC.md); a dynamically linked one needs its own loader path, and a `.so` cannot cross into a bionic process. `opkg` itself can be built, but it would only manage our own shell files -- a tarball + manifest does that in a fraction of the code |
| **LuCI apps** | `luci-app-*`: Makefile + `menu.d/*.json` + `rpcd/acl.d/*.json` + ucode controller + JS view | **No, not cheaply.** The JSON files are inert without uhttpd + ucode + rpcd + ubus + uci + the LuCI client runtime; that is the full stack, weeks of work (see OPENWRT.md) |
| **daemon plugin ABI** | uhttpd `plugin.c` (`dlopen` + dispatch table), rpcd `plugin.c` (ubus methods + ACL), netifd protocol handlers | **No.** Each is tied to the daemon it plugs into, and those daemons are not ported |
| **shell / init plugins** | `rc.common` + `/etc/init.d` + jshn/procd triggers | **Partly.** `rc.common` runs on mksh (tested). Anything using `procd_*` needs jshn + `ubus` + procd, which Android does not have |

So the famous ecosystem itself does not transplant. What transplants is the **shape**: a plugin is a
directory that adds files to well-known places, discovered without touching the core.

## What this tree already has (tested)

A plugin surface exists today, with zero code changes:

```
etc/status.d/99-plugin      -> new status tab + block      (status.cgi scans the directory)
bin/openar-plugin           -> new service tab + status    (services.cgi scans bin/openar-*)
etc/www/cgi-bin/view/*.cgi  -> the page itself, reachable by URL
```

Test: dropping those two files on the deployed tree made a "Test Plugin" tab appear on Status, a
"plugin" tab on Services and `block.cgi?s=plugin&v=status` return `plugin=yes` -- without editing
any core file.

## Gaps before it is a real plugin system

| gap | today | change needed | effort |
|---|---|---|---|
| commands | one `etc/commands` / `commands.default`; an owner copy replaces everything | merge `etc/commands.d/*.list` on top, id-level precedence | 1 day |
| menu | `MENU` is hardcoded in `openar-web-lib` | read `etc/menu.d/*.menu` (url|title|order) | 0.5 day |
| act permissions | one global `ACT_VERBS` list | `plugin.conf` declares its own act verbs; run.cgi checks both | 0.5 day |
| install / remove | files pushed by hand; next `deploy.sh` replaces `bin/` and `etc/www`, so the plugin is lost | `tools/plugin.sh install|remove|list` into `etc/plugins/<name>/`, materialised at start, preserved by deploy | 1-2 days |
| provenance | a service tab looks like any other | record plugin name/version in `etc/plugins.conf`, show it on Services | 0.5 day |
| feed / updates | none | index file + sha256 + version; still shell only | +1 week |

## What a plugin can and cannot be

Can: status blocks, commands, services (`status/check/apply`), CGI pages, CSS/JS assets, help text,
and native payloads that are **static musl** (they run as-is). Dynamic musl payloads need a loader
wrapper, and a `.so` plugin only works inside a host that is itself musl (no cross-libc `dlopen`).
Cannot: LuCI/ucode JS apps, ubus RPC, anything that assumes `/etc/init.d`, uci or procd.

Security: a plugin is shell code running as the tree's user (shell, or root in root mode). Therefore
installation stays **owner-initiated over ADB**; no upload from the web, no network feed in v1.
ACT verbs declared by a plugin are still gated by the two-step POST + Host/Origin checks.

## Recommendation

Build "openar plugins = directory + manifest", not "OpenWrt packages". The first three gaps
(commands.d, menu.d, act verbs) are a ~2-day change and make third-party additions natural; the
install tool and preservation across deploy add another couple of days. That is the cheapest way to
get the *feel* of OpenWrt's plugin model while staying inside Android's rules.
