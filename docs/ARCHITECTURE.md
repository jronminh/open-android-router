# Architecture

The project is deliberately small: a shell tree that can be read, edited and debugged over ADB,
plus a thin web layer over it. Root is an enhancement, not a requirement.

## Layers

```
core/                 the runnable tree (deployed as-is to <root>/)
  bin/openar-web     supervisor: one busybox httpd per interface IP, respawned like procd
  bin/openar-web-lib page frame/widgets (LuCI Bootstrap look)
  bin/openar-cmd     command list from the shell
  lib/openar-platform.sh  mode detection: root|shell, interfaces, port, busybox, logging
  lib/openar-commands.sh  read/validate/run a command from etc/commands(.default)
  etc/www/           docroot: index, openar.js, cgi-bin/{view,act}
  etc/status.d/      one file per status block (first line: "# title: ...")
  etc/commands.default   the vetted command list
  etc/web.conf.example   interfaces + port (owner copy: etc/web.conf)
  etc/httpd.conf.example Basic auth password (owner copy: etc/httpd.conf)
platform/<mode>/     deployment defaults (ifaces, port, busybox search) -- see platform/README.md
devices/<name>/      a device pack: overlays etc/, bin/ or lib/ of the tree
tools/build_tree.sh  core/ + devices/<name> -> out/<name>/
tools/deploy.sh      build, push, keep owner config, set first-run files
tools/check.sh       the floor check: pages, a status block, one command
```

## Runtime resolution

Every entry point sets `OPENAR_ROOT` from its own location, so the tree works wherever it is
copied (`bin/openar-*` -> one level up; `etc/www/cgi-bin/*/*.cgi` -> four levels up), and sources
`lib/openar-platform.sh`. Deployments may override it with `OPENAR_ROOT` for tests.

## Busybox first

The portability contract is busybox, not toybox. Toybox applets and options change with the AOSP
version (`cmd` exists only from 7.0, `ip` is not a toybox applet at all, `mktemp`/`top` availability
varies), so every POSIX tool comes from one busybox through a symlink farm created at deploy:

```
bin/busybox          the operator's static busybox (GPL-2.0, not shipped in this repo)
bin/shims/<applet>   symlink -> ../busybox; PATH puts bin/shims first
```

The shimmed set is fixed and printed by `deploy.sh`: `awk base64 cat cut date df dirname egrep
fgrep find grep head ip mktemp mkdir mv printf readlink realpath rm sed seq sha256sum sleep sort
stat tail tar timeout top touch tr uniq wc xargs gzip`.

Deliberately **not** shimmed: `ping` (busybox ping needs root, Android's does not), `sh` (mksh gives
`print -r`), and the framework commands `getprop settings svc pm am dumpsys logcat`. `cmd` and
private DNS are not used by core, because they do not exist on the floor (Android 6.0).

## Modes

`openar-platform.sh` sets `OPENAR_MODE=root` when `id -u` is 0, else `shell`. From it:

| capability | root | shell |
|---|---|---|
| web port default | 80 | 8080 |
| interfaces default | `usb0 swlan0` | `lo` |
| kernel log (`/dev/kmsg`) | written | skipped (`[ -w /dev/kmsg ]`) |
| owner config | `etc/web.conf`, `etc/httpd.conf` | same |
| boot durability | `/data/adb/service.d/openar-web.sh`, installed by `deploy.sh --root` | none |

## Target: a node, not a phone

The device is expected to be a **dn-cluster node**: stock firmware, then the consumer surface
removed over adb (G48) -- on the reference 701SH about 52 packages survive, with no launcher,
keyboard, Settings, SystemUI, telephony, Bluetooth, WebView, MTP, media or contacts provider.
A small device owner (G49) provides HOME and policy, the screen is off, and a master controls the
node over ADB.

openar must run in that state:

- ADB + busybox httpd are the only surfaces; no Settings/launcher/WebView to lean on;
- blocks print `n/a` and commands fail with their own message when the package or service behind
  them has been trimmed away (SMS needs its provider, IMS needs its vendor service);
- state lives in `/data` files, never in an app sandbox;
- early calls must tolerate the framework not being ready: after a reboot adb answers at ~27-30 s,
  the package manager at ~31-33 s, `sys.boot_completed` at ~35-38 s.

### Runtime boundaries and ART

The tree runs as ordinary shell processes under adbd/init. It ships no APK by default, no zygote
and no WebView, so the web UI keeps answering with the screen off or the app layer broken. If a
capability needs an app (device owner, HOME, a policy), the app follows the `nodeapp` shape: a few
KB, passive, one broadcast command at a time, direct-boot aware -- an actuator, not the product.

"Independent of ART" is not literally true, and the documentation says so. Measured on Sharp
(Android 10) and S21 (Android 15):

| command | implementation | ART? |
|---|---|---|
| `cmd`, `dumpsys`, `logcat`, `getprop`, `service` | native binaries | no |
| `settings`, `pm` | shell wrapper -> `cmd settings` / `cmd package` | no |
| `am` (except `am instrument`) | shell wrapper -> `cmd activity` | no |
| `content` | `app_process content.jar` | **yes, every call** |
| `svc` | Android 10: `app_process svc.jar`; Android 15: wrapper -> `cmd` | 10: yes, 15: no |

Consequence: a broken `system_server` breaks framework actions (SMS read, some `svc` verbs, any
`cmd` call) while ADB and the web UI stay up. The cost of the ART-backed tools is a one-shot runtime
start per call (the SMS query is ~1.3 s for that reason).

## Web layer

- `busybox httpd` per interface address from `etc/web.conf`; a supervisor loop keeps them up
  (threshold 3600 s, retry 5, restart after 5 s -- the procd instance policy).
- HTTP Basic, one password for the whole site, `etc/httpd.conf` outside the docroot, mode 0600.
- Pages: Status (blocks), Clients (neighbour table), Services, Commands, SMS, Logs. Each page
  sends its frame immediately; blocks load in parallel through `cgi-bin/view/block.cgi`, like
  LuCI's "Loading view..." spinner.
- The treeless URL `/` is a redirect; `openar.js` fills `data-block`/`data-cmd` placeholders.
- Optional friendly names (`names="openar.lan"` in `etc/web.conf`) are written as `<ip> <name>`
  lines into the hosts file the tether dnsmasq reads, with a SIGHUP afterwards; root plus Magisk
  systemless hosts only. The act zone accepts those names as `Host` as well (still safe against
  DNS rebinding: a rebinding page carries the attacker's own name).

## Services

A service is a script `bin/openar-<name>` with a `VERBS="..."` line and one `svc_<verb>` function
per verb (`lib/openar-service.sh`). Core ships `web`, `tether`, `radio`, `battery`, `wifi`,
`adb` (rescue settings), `otablock` (`etc/otablock.list`) and `hotspot` (root-only, `cmd wifi
start-softap`, `etc/hotspot.conf`). Read-only verbs are `status` (key=value lines) and `check`
(exit 0 means "in line with intent", otherwise it prints `diff ...`). The services page lists every
such script, loads `status`/`check` through `block.cgi?s=&v=`, and turns act verbs listed in
`ACT_VERBS` into POST buttons to the act zone. Core ships `tether`, `radio`, `battery`, `wifi`
and `web`; device packs add more.

## SMS

Read: `content query --uri content://sms/<box>` (no app, no database access). Send: the isms binder,
transaction 5 (`sendTextForSubscriber`), as uid 2000 -- a root-mode web process uses Magisk
`su 2000`; a rootless one already is 2000 and passes the text as one argv element (no shell
re-parsing). One part only (160 ASCII / 70 non-ASCII); shortcodes (1-5 digits) are refused because
Android shows a premium-SMS confirmation dialog for them. A device without an SMS provider reports
the provider error instead of showing an empty inbox.

## Commands

`etc/commands.default` is tab-separated:

```
id  section  group(auto|view|act)  confirm  timeout_s  param_regex  description  command
```

A parameter is appended as one single-quoted word and must match `param_regex`; `-` means none.
Package control goes through `bin/openar-pkg` (state/disable/enable/stop), which validates the name
and refuses `android` / `com.android.shell`: disabling either would cut ADB, the rescue path.
Zones: `view` (web GET) runs auto|view; `act` (web POST) runs act only; `any` (ADB) runs
everything. Refusal is explicit: unknown id, wrong zone, missing or non-matching parameter all
return exit 2 with a message. Output is capped at 512 KB; stdout/stderr go through pipes because
system_server may not write our files (SELinux `adb_data_file`).

## Act zone

`cgi-bin/act/run.cgi` is the only place the web changes state: POST only; `Host` must be one of
the IPs the tree serves (blocks DNS rebinding); `Origin`/`Referer` must match it (blocks CSRF);
a second POST with `confirm=yes` executes; every act run appends to `var/log/actions.log`.

## Logs

- `var/log/openar.log`: one line per command/service event (always).
- `var/log/actions.log`: state changes (always).
- `var/log/web.log`: supervisor and httpd output.
- Kernel log: only when writable (root); the openar log is the portable source of truth.

## Adding a device

1. `devices/<name>/` with `etc/` files it wants to change: `web.conf`, `httpd.conf`,
   `commands`, `status.d/` blocks. Files there overlay `core/`.
2. `tools/build_tree.sh <name>`, `tools/deploy.sh <serial> --pack <name>`.
3. `tools/check.sh <serial>` must pass before the device is called supported.

## Roadmap

- More device packs: `g990e` is the reference; the S10 (`g970w`) and the 701SH go next.
- Service abstraction (start/stop/status/apply) once there is more than one service.
- Boot persistence for rooted devices (Magisk service) -- deliberately not ported yet.
