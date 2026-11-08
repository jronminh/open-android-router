# OpenWrt tree compatibility

> Research note, not a roadmap. The scope is device capabilities plus the OpenWrt-shaped
> management layer; the ideas here are recorded in [IDEAS.md](IDEAS.md), not planned.

This is the first compatibility layer: if the tree layout matches OpenWrt's rootfs, scripts and
plugins land where they expect. Measured against the pinned source in the personal project
(OpenWrt v25.12.6, `package/base-files`) and on a SHARP 701SH (Android 10, rootless), 2026-11-08.

## OpenWrt rootfs (base-files)

```
/                bin  etc  lib  rom  sbin  usr  www  tmp
/var             -> tmp                 (symlink)
/var/run         -> /tmp/run           (symlink)
/etc             config/ init.d/ rc.d/ uci-defaults/ hotplug.d/ board.d/
                 profile.d/ sysctl.d/ rc.button/ rc.common rc.local preinit
                 banner* device_info diag.sh ethers fstab group hosts inittab
                 openwrt_release openwrt_version os-release passwd profile
                 protocols services shadow shells shinit sysctl.conf sysupgrade.conf
/etc/config      network system ...    (UCI)
/etc/init.d      boot done led sysctl system ...  (kept as files)
/etc/rc.d        S??<name> K??<name>   (symlinks to init.d, created by enable)
/lib             functions.sh functions/ preinit/ upgrade/
/sbin            firstboot hotplug-call led.sh pkg_check sysupgrade
/usr             bin/ sbin/ lib/ share/
/www             docroot
/tmp             mode 1777
```

Install rules worth knowing: `/tmp` is 1777, `/var` is a symlink to `tmp`, `/var/run` to
`/tmp/run`, `/etc/rc.d` and `/etc/config` are directories created at install, and files under
`/etc/config` are registered as conffiles (preserved on upgrade).

A LuCI application (`luci-app-*`) is a package that lays itself out as:

```
root/usr/share/luci/menu.d/*.json     menu entries (title, order, action, acl depends)
root/usr/share/rpcd/acl.d/*.json      permissions (uci read/write, ubus, file paths)
htdocs/luci-static/resources/view/*   client-side JS views
ucode/controller/*.uc                 server-side controllers
po/                                   translations
```

## Our tree today

```
bin/            openar-web, openar-cmd, openar-sms, openar-<service>, openar-airplane
lib/            openar-platform.sh, openar-commands.sh, openar-service.sh, openar-sms.sh
etc/            commands(.default), web.conf, httpd.conf, status.d/, menu hardcoded
etc/www/        docroot (index, openar.js, cgi-bin/, luci-static/)
var/            log/, run/, tmp/   (real dirs, not symlinks)
home/  VERSION
```

## Gap map

| OpenWrt | ours | adopt? | effort |
|---|---|---|---|
| `/www` at the root | `etc/www` | **yes**, mechanical (about 10 references) | 0.5 day |
| `/etc/init.d` + `/etc/rc.d` S/K links | `bin/openar-*` auto-discovered | **yes**: thin `etc/init.d/openar-<name>` wrappers, rc.d links for enable/disable | 1 day |
| `/lib/functions.sh`, `rc.common` | our own dispatch | **partly**: rc.common runs on mksh (tested, `START-OK`, `rc=0`); config_load needs uci | 0-1 day |
| `/etc/config` (UCI) | `etc/web.conf`, `etc/httpd.conf` | optional; needs `uci` binary + reader changes | 2-3 days |
| `/usr/share/luci/menu.d` + `rpcd/acl.d` JSON | hardcoded MENU + `ACT_VERBS` | **schema yes, runtime no**: needs a JSON reader (jshn-like) | 1-2 days |
| `/etc/uci-defaults` | deploy first-run | yes, trivial rename/mapping | 0.5 day |
| `/rom` + overlay | none | **no**: Android has no overlay root; durability = boot image / Magisk | - |
| `/etc/opkg`, `/usr/lib/opkg` | none | **no**: package format is OpenWrt/musl; see PLUGINS.md | - |

## Two traps found by running the shell layer

1. `rc.common` itself works, but `config_load` silently returns **0** when `uci` is absent
   (`uci_load` missing, no error). An OpenWrt init script would look like it ran while loading no
   config at all. Any adoption of `functions.sh` must either vendor `uci` or make this failure loud.
2. procd helpers are not shell-only: `_procd_ubus_call` goes through jshn + `ubus` + the procd
   daemon. So "rc.common works" must not be read as "OpenWrt init scripts work".

## The absolute-path wall

OpenWrt scripts hardcode `/etc/...`, `/usr/...`, `/var/...`. On Android those are read-only
system paths; this tree lives under `/data/adb/openar` (root) or `/data/local/tmp/openar` (shell).
Consequences:

- **PATH-invoked tools can be shimmed**: shipping a `uci` wrapper that adds
  `-c $OPENAR_ROOT/etc/config`, or an `init.d`-style helper, makes calls like `uci get` work.
- **Hardcoded file paths cannot be shimmed** without a chroot/proot and root; that is not acceptable
  for a rootless floor (and SELinux makes it fragile even rooted).
- Therefore an **OpenWrt plugin dropped in unchanged will not work** in general; only plugins written
  against our paths (or PATH tools) do. That is the honest ceiling of "tree compatibility".

## Recommended order

1. **L0 (paths/naming, ~2 days):** `www/` at root; `etc/init.d/` wrappers + `etc/rc.d/` links;
   `etc/uci-defaults/`; keep `bin/openar-*` as the implementation. No behavior change, big
   navigability win for anyone from OpenWrt.
2. **L1 (metadata, ~2 days):** read `etc/menu.d/*.json` and `etc/acl.d/*.json` (flat subset of the
   LuCI schema) with a small awk/sed reader, falling back to today's built-in MENU/ACT_VERBS.
3. **L2 (config, 2-3 days, optional):** static `uci` build + wrapper + move web/httpd config into
   `etc/config/`. Only worth it if plugins are expected to use `uci get`.
4. **Do not:** opkg/.ipk, overlay/rom, ubus/rpcd/procd, full LuCI.

L0 is the cheapest real step toward "tree compatibility"; it changes no security property and can be
verified by the existing floor check.
