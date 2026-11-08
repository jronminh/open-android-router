# open-android-router (openar)

Turn an Android phone into a small network device -- USB tethering / hotspot as the uplink --
with a web UI that works **without root**, and takes advantage of root when it is there.

Status: **0.1, early**. The tree came out of a personal project (S21Net, a Galaxy S21 FE acting
as a 4G router); this repository keeps only the device-agnostic parts: web UI, native command
layer, platform layer, deployment and checks. Device specifics live in `devices/`.

## What works

- **Status page**: device, battery, network interfaces, cellular signal, and the web service
  itself. Each block is a file in `src/etc/status.d/`; add or remove files to add or remove blocks.
- **Commands page**: a vetted list of native Android commands (`settings`, `svc`, `cmd`, `ip`,
  `dumpsys`, ...) with a per-command parameter regex, timeout and 512 KB output cap. Read-only
  commands run on demand; "act" commands change state through a POST zone with a second
  confirmation and a log line per run.
- **Logs page**: actions, web supervisor, openar log, crash buffer.
- **No root needed** for: serving the UI, reading status, running read-only commands, and most
  `settings`/`svc`/`cmd` actions (ADB shell holds many of those permissions).

## Modes

| | root (Magisk or similar) | plain shell (no root) |
|---|---|---|
| tree path | `/data/adb/openar` | `/data/local/tmp/openar` |
| web port | 80 | 8080 |
| default interfaces | `usb0 swlan0` | `lo` (use `adb forward`, or add `wlan0`) |
| kernel log | yes | no (falls back to `var/log/openar.log`) |
| durability across reboot | boot hook / Magisk service | none (start it over ADB) |

The capability differences are detected at runtime by `src/lib/openar-platform.sh`; nothing
in `src/` may assume root. A feature that needs root must say so and degrade cleanly.

## Quick start (no root)

```sh
# from the repo, with a device attached over ADB
tools/deploy.sh <serial> --shell
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
src/        the runnable tree: bin/ lib/ etc/ var/
devices/    per-device packs (extra config, command lists, status blocks)
tools/      build_tree.sh, deploy.sh, check.sh
docs/       ARCHITECTURE.md
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

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): layers, modes, capability matrix, security model.
- [devices/generic/README.md](devices/generic/README.md): what a device pack can override.

## License

Apache-2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). busybox is used at runtime under its own
license (GPL-2.0) and is not part of this source tree.
