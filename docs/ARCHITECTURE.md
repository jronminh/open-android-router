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
| boot durability | outside this tree (Magisk service / boot hook) | none |

## Web layer

- `busybox httpd` per interface address from `etc/web.conf`; a supervisor loop keeps them up
  (threshold 3600 s, retry 5, restart after 5 s -- the procd instance policy).
- HTTP Basic, one password for the whole site, `etc/httpd.conf` outside the docroot, mode 0600.
- Pages: Status (blocks), Commands (list), Logs. Each page sends its frame immediately; blocks
  load in parallel through `cgi-bin/view/block.cgi`, like LuCI's "Loading view..." spinner.
- The treeless URL `/` is a redirect; `openar.js` fills `data-block`/`data-cmd` placeholders.

## Commands

`etc/commands.default` is tab-separated:

```
id  section  group(auto|view|act)  confirm  timeout_s  param_regex  description  command
```

A parameter is appended as one single-quoted word and must match `param_regex`; `-` means none.
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

- Device packs for the S21 FE (root: tether/profile intent, boot hook) and the Sharp 701SH
  (rootless reference).
- Service abstraction (start/stop/status/apply) once there is more than one service.
- Optional DNS name for the UI (needs systemless hosts; root only, off by default).
