# libc on Android (musl, glibc, bionic)

> Research note, not a roadmap. The scope is device capabilities plus the OpenWrt-shaped
> management layer; the ideas here are recorded in [IDEAS.md](IDEAS.md), not planned.

Earlier notes in this repository said "OpenWrt binaries are musl and therefore cannot run on
Android". That is too coarse. The measured picture (personal notes `deb-native-notes`, and two
Termux projects) is:

## What actually happens

| binary | direct exec | works how |
|---|---|---|
| static musl | **yes** | no interpreter needed (e.g. a static dropbear built with musl ran on the S21) |
| dynamic musl | no (kernel wants `/lib/ld-musl-aarch64.so.1`) | invoke the musl loader explicitly with a private `--library-path`; a Termux project runs the official OpenCode musl release exactly this way |
| dynamic glibc | no (kernel wants `/lib/ld-linux-aarch64.so.1`) | a loader wrapper: Termux `glibc-runner` (`grun`), or `ld-dn` in `deb-native` |
| `.so` plugin | - | **no cross-libc `dlopen`**: a bionic process cannot load a musl library. An all-musl host (uhttpd built against musl) can load musl plugins |

So the wall is not "musl vs bionic" in general; it is **interpreter paths, dynamic-loader selection,
and never mixing libc inside one process**.

## The domain matters more than the libc

Android's per-process **seccomp filter** is built from bionic's syscall list and answers unknown
syscalls with `SIGSYS`, not `ENOSYS`. Measured consequences in the personal notes:

- a **static musl busybox starts, then dies at its own `setgid`** in the app/Termux domain;
- glibc 2.41 issues two trapped syscalls **before `main`** there;
- the **shell domain has no seccomp filter at all** (`Seccomp: 0`), and a rooted process likewise.

Measured on this project's devices (2026-11-08): `u:r:shell:s0` and the Magisk root process both
report `Seccomp: 0`. That is why this tree, which runs over `adb shell` or Magisk, is a friendlier
host for foreign-libc tools than Termux is — Termux is an app and only gets away with glibc through
a loader plus an old `targetSdk`.

## What still blocks, independent of libc

- **Absolute paths**: OpenWrt tools want `/etc`, `/usr`, `/lib`; the kernel resolves `PT_INTERP`
  before any userspace code runs, so a wrapper cannot fix it for a foreign binary. That is why
  `deb-native` needs a tracer (`dn-init`) plus a preloaded shim (`dn-lane.so`) and a userland exec
  (`ld-dn`) to run an unmodified Debian tree with no chroot and no root.
- **android init owns PID 1** (procd cannot be init), and SELinux still gates executing files and
  `dlopen` of libraries a process wrote itself.
- **The UI stack** (LuCI/ucode) is missing regardless of how the binaries are linked.

## Consequence for this project

- Building `uhttpd`/`ubus`/`rpcd` as a **static-musl island** and running it from the tree is more
  plausible than the earlier note suggested; their C dependencies are ordinary userspace.
- It would still not be "OpenWrt compatible": no pid 1, no absolute `/etc`, and a plugin `.so` only
  works if the host process is the same musl island.
- Native plugin payloads can be considered in two forms: **static musl** (runs as-is) and **dynamic
  musl** (needs a loader wrapper). Anything prebuilt for OpenWrt that is dynamically linked will
  need the same treatment as any other foreign binary.
