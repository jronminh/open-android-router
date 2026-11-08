# AGENTS.md -- how we work on open-android-router

Read [README.md](README.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first. This file is
the workflow contract, kept short. Change it when the way we work changes.

## What this repository is

- One shell tree (`core/`) that turns an Android phone into a small network device with a web UI.
- Two modes from one tree: **root** and **plain shell**. The plain shell is the floor.
- Device specifics belong in `devices/<name>/`; `core/` stays device-agnostic.
- The old personal S21Net repository is the origin story, not a dependency. Never copy its
  device secrets, keys or evidence into here.

## Environment

- Reference platform: **Linux** -- native or **WSL2**. Host tooling is POSIX `sh`, and Android's
  shell is mksh/toybox, so a Linux shell is the closest match. Prefer it over Windows-native shells.
- On Windows, use **WSL** when it is installed (edit and run host scripts there). ADB inside WSL
  only sees phones attached through **usbipd-win** (`usbipd list`, `usbipd attach --wsl --busid <id>`);
  without that, WSL's adb reports no devices.
- Windows fallback: **Git Bash** with the Windows adb. `tools/deploy.sh` and `tools/check.sh` set
  `MSYS_NO_PATHCONV=1` themselves -- do not remove it, and never hand a `/data/...` path to a
  native Windows tool without it.
- Measured on the project workstation, 2026-11-08: WSL Debian has adb 34.0.5 but no USB attached;
  Windows adb 1.0.41 + Git Bash passes the floor check on both test devices.
- Put commands in a script and push it; avoid long one-liners through PowerShell -> adb. Quoting is
  eaten twice (PowerShell, then the device shell) and the failure looks like a device bug.

## Test devices

| role | device | notes |
|---|---|---|
| rootless reference (the floor) | SHARP 701SH, Android 10 | no root, no SMS provider |
| root reference | Galaxy S21 FE (SM-G990E) | production uplink: do not reboot or change settings without the owner's consent |

Test order: rootless first, root second. If something only works with root, document it in the
capability matrix instead of merging it silently.

## Hard rules

1. **Rootless floor.** Every page, command and service must work with `adb shell`, or state that it
   needs root and degrade cleanly. `tools/check.sh --mode shell` must pass. The floor is
   **Android 6.0**; do not add a tool or a flag that only exists in a newer AOSP (no `cmd`,
   no private DNS in core).
2. **Busybox first.** POSIX tools come from busybox through `bin/shims` (created by `deploy.sh`);
   framework commands come from the system. Never call a bare toybox applet in new code, never
   assume a toybox option, and never commit the busybox binary (GPL-2.0, supplied by the operator).
3. **No state that exists only in the UI.** Every control maps to a file in `etc/` or a command in
   `bin/`; the web is a view over the command line, never a second implementation.
4. **Official Android mechanisms only**: `svc`, `settings`, `pm`, `am`, `dumpsys`.
   No iptables, no rootfs tricks, no persistent Linux-layer hacks.
5. **Bind per interface, never 0.0.0.0.** Interfaces and port come from `etc/web.conf`.
6. **Secrets stay out of git.** Only `*.example` files in `core/etc/`; `etc/httpd.conf` is created on
   the device (mode 0600) and never committed.
7. **The act zone stays small and loud**: POST only, Host and Origin checks, a second confirmation,
   one log line per run.
8. **Commands are vetted**: every row has a group, a timeout, a parameter regex and a description.
   Read-only commands never get the `act` group.

## Definition of done

1. `tools/build_tree.sh <pack>` builds; `tools/deploy.sh <serial> --shell` and `--root` install
   cleanly and keep the owner's config.
2. `tools/check.sh <serial> --mode shell` and `--mode root` pass on real devices.
3. `README.md` and `docs/ARCHITECTURE.md` updated when behavior or the capability matrix changes.
4. One logical change per commit; message `area: what changed (evidence)` in English. Never commit
   `out/`, logs, busybox binaries or secrets.

## Adding a device pack

Create `devices/<name>/` with only the files that differ (`etc/web.conf`, `etc/commands`,
`etc/status.d/...`), build and deploy with `--pack <name>`, run the floor check, and write the
device's quirks in `devices/<name>/README.md`.

## Things we learned the hard way

- `adb forward` only reaches device loopback; a server bound to a LAN IP (root mode) is invisible to
  it. Root checks therefore test from the device side or from the LAN.
- busybox httpd binds exactly the address it is given. A supervisor must watch the interface
  address, not only the process.
- A fresh `adb forward` refuses the first connections: wait about a second or retry.
- Magisk `su 0 <cmd>` silently does nothing; use `su -c '<cmd>'`.
- toybox `tar` cannot chown as shell; extract with busybox tar or tolerate the chown errors.
- On Android 10/15, system_server cannot write our files in app data (SELinux `adb_data_file`);
  route `cmd`/`settings` output through pipes.
