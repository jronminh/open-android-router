# open-android-router (openar)

Turn an Android phone into a small network device -- USB tethering / hotspot as the uplink --
with a web UI that works **without root**, and takes advantage of root when it is there.

Status: **0.1, early**. The tree came out of a personal Android router project; this repository
keeps only the device-agnostic parts: web UI, native command layer, platform layer, deployment and
checks. Device specifics live in `devices/`.

## Platform support

| axis | supported |
|---|---|
| ROM family | **One UI** (Samsung stock) and **AOSP-based** Android builds; custom ROMs are untested |
| Android | **6.0 (API 23) and newer**; verified on 10, 12 and 15 -- see [docs/SUPPORT.md](docs/SUPPORT.md) |
| modes | **rootless** `adb shell` (the floor) and **root via Magisk** only |
| architecture | any, as long as the operator-supplied busybox matches the device (arm64 tested) |

Other `su` implementations and custom ROMs are out of scope for now: the tree assumes the
framework commands and the security model of stock One UI / AOSP-based builds.

## Scope (and non-goals)

The project does two things and nothing else:

1. **Expose what the device already has**: tether and interfaces, radios, battery, SMS if the
   device has a provider -- through one small web UI, with the rootless shell as the floor.
2. **Keep the management layer OpenWrt-shaped** (service verbs, a vetted command list, status
   blocks, one password, act zone) because that model is proven for headless boxes.

It is **not** a port of OpenWrt: no `opkg`/`.ipk`, no `uhttpd`/`ubus`/`rpcd`/`procd`/`LuCI`,
no libc island, no plugin feed. Those are recorded in [docs/IDEAS.md](docs/IDEAS.md) as ideas, not
planned. New work should add a *device capability* or simplify the *management layer*, not a
component from another system.

## Philosophy

- **Headless-first.** The device needs no screen, launcher or Settings app. ADB and the web UI are
  the setup and rescue paths; every control is a file in `etc/` or a command in `bin/`, so nothing
  lives only in an app's UI. The tree keeps working with the screen off.
- **No dependence on the Android surface.** It runs on any supported device, but the floor is
  that the management layer needs no Android UI: no Settings, launcher or SystemUI. The same tree
  runs on a trimmed node; details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What works

- **Status page**: device, battery, network interfaces, cellular signal, traffic counters and the
  web service itself. Each block is a file in `core/etc/status.d/`; add or remove files to add or
  remove blocks.
- **Clients page**: the neighbour table (ARP/ND) with address, interface, MAC and state -- the
  devices this one has talked to. Android does not export the tether DHCP leases to a shell, so a
  client appears after its first packet.
- **Traffic**: per-interface byte counters and rate from `/proc/net/dev` (USB, Wi-Fi, hotspot,
  Ethernet, mobile data); interfaces with no traffic are hidden.
- **Commands page**: a vetted list of native Android commands (`settings`, `svc`, `pm`, `am`,
  `dumpsys`, `ip`, ...) with a per-command parameter regex, timeout and 512 KB output cap. Read-only
  commands run on demand; "act" commands change state through a POST zone with a second
  confirmation and a log line per run.
- **Services page**: every `bin/openar-<name>` with a `VERBS=` line is a service; read-only
  verbs (`status`, `check`) load by themselves, act verbs (`apply`, `airplane-toggle`) go through
  the act zone with confirmation and logging.
- **SMS page**: inbox and sent through Android's SMS content provider, and a one-part send through
  the `isms` binder. Shortcodes (1-5 digits) are refused; the page needs an SMS provider.
- **Logs page**: actions, web supervisor, openar log, crash buffer.
- **Package and SIM control**: read a package's state, disable/enable it (`pm disable-user`), or
  force-stop it (`am force-stop`); a small deny list refuses `android` and `com.android.shell` so
  the ADB rescue path cannot be cut. SIM state and operator are read from `getprop`.
- **ADB rescue and OTA block services**: `openar-adb` keeps ADB on with no authorization timeout
  (the headless rescue path); `openar-otablock` disables the packages listed in
  `etc/otablock.list` (empty by default; device packs ship the vendor list). Both work rootless.
- **Boot persistence (root)**: `deploy.sh --root` installs `/data/adb/service.d/openar-web.sh`, so
  the web UI comes back after a reboot or power loss. `--no-boot` skips it.
- **No root needed** for: serving the UI, reading status, clients, traffic, mobile data *state*,
  registration, Wi-Fi on/off (tested), and most `settings` actions.
- **Root only**: tether `apply`, mobile data on/off (`svc data` hangs for uid shell -- measured),
  hotspot (`cmd wifi start-softap` is root-only), and the friendly DNS name. These refuse fast with
  exit 3 instead of hanging.

## Modes

| | root (Magisk or similar) | plain shell (no root) |
|---|---|---|
| tree path | `/data/adb/openar` | `/data/local/tmp/openar` |
| web port | 80 | 8080 |
| default interfaces | `usb0 swlan0` | `lo` (use `adb forward`, or add `wlan0`) |
| kernel log | yes | no (falls back to `var/log/openar.log`) |
| durability across reboot | Magisk `service.d` hook (installed by deploy) | none (start it over ADB) |

The capability differences are detected at runtime by `core/lib/openar-platform.sh`; nothing
in `core/` may assume root. A feature that needs root must say so and degrade cleanly.

The URL is normally the device IP (or `adb forward` + `127.0.0.1`). A friendly name is optional:
`names="openar.lan"` in `etc/web.conf` publishes it through the tether DNS, so
`http://openar.lan:8080/` works; that needs root plus Magisk's systemless hosts and is ignored
elsewhere. The act zone accepts the name as `Host` too.

## Busybox first (the portability contract)

Toybox applets and their options differ between AOSP versions (`cmd` only exists from Android 7.0,
`ip` is not even a toybox applet), so the tree does not rely on toybox. POSIX tools come from
**busybox** through `bin/shims`, a symlink farm created at deploy time:

| layer | source |
|---|---|
| POSIX tools | busybox: `sed awk grep ip timeout mktemp top df date tar ...` |
| framework | system: `getprop settings svc pm am dumpsys logcat` |
| exceptions | system: `ping` (busybox ping needs root), `sh` (mksh) |

BusyBox is GPL-2.0 and is **not** shipped here. The deploy script uses a busybox already on the
device, or one you pass with `--busybox PATH`; `tools/get_busybox.sh` pulls Magisk's copy from a
rooted phone. The floor is **Android 6.0**; see [docs/SUPPORT.md](docs/SUPPORT.md) for exactly what
has been verified on which device.

## Quick start (no root)

```sh
# from the repo, with a device attached over ADB
tools/deploy.sh <serial> --shell [--busybox PATH]   # --busybox needed only if the phone has none
adb -s <serial> shell /data/local/tmp/openar/bin/openar-web start
adb -s <serial> forward tcp:8080 tcp:8080
# open http://127.0.0.1:8080/ with the credentials from etc/httpd.conf (admin/admin until changed)
tools/check.sh <serial>
```

## Quick start (root)

```sh
tools/deploy.sh <serial> --root
adb -s <serial> shell /data/adb/openar/bin/openar-web start
# open http://<usb0 IP>/ (e.g. the tether gateway address)
tools/check.sh <serial>
```

The deploy script copies a `busybox` that already exists on the device (`/data/adb/magisk/busybox`,
`/data/local/tmp/busybox`) into `bin/busybox`; this repo does not ship the binary.

## Layout

```
core/        the runnable tree: bin/ lib/ etc/ var/
platform/    deployment defaults per mode: root/ and shell/
devices/     per-device packs (extra config, command lists, status blocks)
tools/       build_tree.sh, deploy.sh, check.sh
docs/        ARCHITECTURE.md
```

## Rules of the project

1. **The rootless shell is the floor.** Every page, command and service must work with
   `adb shell`, or state clearly that it needs root and keep working without it.
2. **No state that exists only in the UI.** Every control maps to a file in `etc/` or a command
   in `bin/`; the web is a view over the command line, never a second implementation.
3. **Official Android mechanisms only** (`svc`, `settings`, `cmd`, `pm`, `am`, `dumpsys`).
   No iptables/rootfs trickery, no custom kernel, no persistent Linux-layer hacks.
4. **Bind per interface, never 0.0.0.0.** Each `busybox httpd` instance listens on one address
   from `etc/web.conf`; nothing is exposed to a network that was not chosen.
5. **The act zone is small and loud.** POST only, same-origin, two-step confirmation, one log
   line per run.

## Documentation

- [AGENTS.md](AGENTS.md): how we work -- environment, floor rules, definition of done.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): layers, modes, capability matrix, security model.
- [docs/OPENWRT.md](docs/OPENWRT.md): what of OpenWrt runs on Android as-is, what needs a port, what not to carry over.
- [docs/PLUGINS.md](docs/PLUGINS.md): why OpenWrt's plugin ecosystem does not transplant, and the file-based plugin model this tree can grow.
- [docs/OPENWRT-TREE.md](docs/OPENWRT-TREE.md): OpenWrt rootfs layout vs ours, the absolute-path wall, and the L0-L2 adoption plan.
- [docs/LIBC.md](docs/LIBC.md): musl/glibc/bionic on Android -- what runs as-is, what needs a loader, and why the shell domain is easier than an app.
- [docs/IDEAS.md](docs/IDEAS.md): what was investigated and deliberately left out (OpenWrt components, package feed, libc island, plugin installer).
- [devices/generic/README.md](devices/generic/README.md): what a device pack can override.

## License

Apache-2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). busybox is used at runtime under its own
license (GPL-2.0) and is not part of this source tree.
