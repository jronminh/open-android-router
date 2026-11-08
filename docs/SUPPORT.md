# Support floor

The floor is a **capability contract**, not a version number, but the version target is
**Android 6.0 (API 23)**.

## Platform scope

| axis | supported | notes |
|---|---|---|
| ROM family | **One UI** (Samsung stock) and **AOSP-based** builds | custom ROMs (LineageOS et al.) are untested; vendor `dumpsys` fields may differ |
| Android | **6.0+** | verified 10, 12, 15; 6.0-9 expected, not verified |
| security mode | rootless shell, or root via **Magisk** | other `su` implementations are unsupported: paths and permission model differ |
| CPU | any | busybox must match the device; aarch64 tested |

Scope changes only with evidence: a new ROM family or a 6.0/7.0 device must pass
`tools/check.sh` before it appears in the verified table.

## What "supported" means

A device is supported only when both pass on that device:

1. `tools/deploy.sh <serial> --shell` installs and starts (a rooted device also runs
   `--root`, and must pass both).
2. `tools/check.sh <serial> --mode shell` prints `result: PASS` (likewise `--mode root`).

The check verifies the busybox shims, the web pages, a status block and one command. A device
that fails one item is listed as unsupported with the reason, not "mostly working".

## Tiers

| tier | meaning |
|---|---|
| **Verified** | check.sh PASS on the real device (date in the table) |
| **Expected** | meets the capability contract below, no device tested yet |
| **Unsupported** | missing a required capability, or root without Magisk |

## Why 6.0

- The POSIX utilities are **busybox** (shims in `bin/shims`), so toybox applets and options no
  longer matter: the same busybox gives the same behaviour on every version.
- What remains Android-specific is the framework commands: `getprop`, `settings`, `svc`, `pm`,
  `am`, `dumpsys`, `logcat` -- all present since Android 4.x.
- `cmd` appeared in **Android 7.0** (frameworks/native/cmds/cmd is absent at android-6.0.0_r1 and
  present at android-7.0.0_r1), so the command list does not use it; airplane mode goes through
  `settings` + `am broadcast` instead (`bin/openar-airplane`).
- Private DNS (Android 9+) is not in the core command list; device packs may add it.

**Verified today: Android 10, 12, 15. Android 6.0-9 is expected, not verified** -- it needs a
6.0/7.0 device to run the check before the claim is upgraded.

## Capability contract

| layer | provided by | notes |
|---|---|---|
| POSIX tools | busybox via `bin/shims` | awk base64 cat cut date df dirname egrep fgrep find grep head ip mktemp mkdir mv printf readlink realpath rm sed seq sha256sum sleep sort stat tail tar timeout top touch tr uniq wc xargs gzip |
| Android framework | system binaries | getprop settings svc pm am dumpsys logcat |
| shell | `/system/bin/sh` (mksh) | scripts use `print -r`; do not replace with busybox ash |
| exceptions | system | `ping` (busybox ping needs root), `cmd` and private DNS are not used by core |

## Busybox (not shipped: GPL-2.0)

BusyBox is GPL-2.0 and this repository is Apache-2.0, so the binary is **not** in git. Supply it
one of these ways:

- `tools/deploy.sh ... --busybox <file>` -- a static busybox for the device's arch.
- Leave it out: deploy copies a busybox already on the device
  (`/data/adb/magisk/busybox`, `/data/local/tmp/busybox`, `/system/bin/busybox`).
- `tools/get_busybox.sh <rooted-serial>` pulls Magisk's busybox from a rooted phone (Magisk only).

Tested binary: BusyBox v1.36.1.1 (topjohnwu), aarch64, sha256
`4d60ab3f5a59ebb2ca863f2f514e6924401b581e9b64f602665c008177626651`. Newer builds with the same
applets are fine; `deploy.sh` prints any missing applet.

## Verified devices

| device | Android | SELinux | mode | port | check | notes |
|---|---|---|---|---|---|---|
| SHARP 701SH | 10 | enforcing | shell | 8080 | PASS 2026-11-08 | no SMS provider, no `secims`, Wi-Fi only |
| Samsung SM-G970W (S10) | 12 | **permissive** | shell | 8081 | PASS 2026-11-08 | 8080 already taken by another app; permissive can hide permission bugs |
| Samsung SM-G990E (S21 FE) | 15 | enforcing | root (Magisk) | 8080 | PASS 2026-11-08 | production uplink; root-mode reference; `openar.lan` verified |

Enforcing devices are the referee: a permissive device (S10) can pass where an enforcing one would
fail, so the Sharp/S21 results are the ones that count.

## Adding a device

1. `tools/deploy.sh <serial> --shell [--busybox PATH] [--port N]` (a taken port shows
   `httpd: bind: Address already in use` in `var/log/web.log`; change the port).
2. `tools/check.sh <serial> --mode shell` must print PASS.
3. If behaviour differs (vendor fields, missing services), add only the differences under
   `devices/<name>/` and a row above with the date.

## Known limitations

- Boot persistence is root-only: `deploy.sh --root` installs `/data/adb/service.d/openar-web.sh`.
  Shell mode starts over ADB and does not survive a reboot (by design).
- `openar-adb apply` sets `adb_allowed_connection_time=0` (no re-authorization) because the node
  must be reachable without a screen. That is a deliberate security trade-off for headless rescue.
- `openar-otablock` reads `etc/otablock.list` (empty on a generic tree; `devices/g990e` ships
  Samsung's two firmware updaters). It uses `pm disable-user` as shell, verified on the S10 with a
  test package; a device owner's own package cannot be disabled this way.
- Package control (`pkg-state`, `pkg-disable`, `pkg-enable`, `pkg-stop`) works rootless on the
  tested devices; it refuses `android` and `com.android.shell` so ADB cannot be cut. A device
  owner's own package is protected by the framework and will refuse.
- SIM values are `getprop` strings and vary: dual-SIM builds return comma-separated lists (the S21
  reports `LOADED,ABSENT`), a trimmed node may report `ABSENT`.
- `dumpsys` field names differ by vendor/version; blocks print `n/a` instead of pretending.
- Clients = the ARP/ND neighbour table (`ip neigh`); Android does not export DHCP leases to a
  shell, so a client appears after its first packet and IPv6 neighbours are listed too.
- Traffic = `/proc/net/dev` counters since boot, with the rate measured between page loads; only
  USB/RNDIS/Wi-Fi/hotspot/Ethernet/mobile interfaces are shown, and rows with no traffic are hidden.
- Mobile data **control** is root-only: `svc data` hangs for uid shell on the tested devices
  (measured 2026-11-08) instead of failing, so `openar-data` refuses with exit 3 when not root.
  Reading the state (`data-state`) works rootless. Tether `apply` is root-only for the same
  reason; Wi-Fi on/off works rootless (tested).
- SMS needs an SMS content provider (the Sharp 701SH has none, the page reports the provider error).
  One part per message (160 ASCII / 70 non-ASCII); shortcodes (1-5 digits) are refused because
  Android shows a premium-SMS confirmation dialog for them. The send path is implemented but was not
  exercised on a live number from this repository.
- `airplane` uses `settings` + `am broadcast` (no `cmd`); verified on Android 10 (Sharp) and 12 (S10),
  unverified on 13+ where the framework may restrict broadcasts.
- Friendly names (`names="openar.lan"` in `etc/web.conf`) need root plus Magisk systemless hosts;
  verified on Android 15 (S21 FE, `http://openar.lan:8080/` 200). Shell mode ignores them and the
  IP keeps working.
- Android 6.0-9 is not verified yet.
