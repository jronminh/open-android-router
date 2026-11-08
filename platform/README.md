# platform/

Two platforms, one tree. The tree itself detects where it runs at runtime
(`core/lib/openar-platform.sh`); this directory only holds the **deployment defaults** used by
`tools/deploy.sh`, so the differences between a rooted box and a plain shell box are visible in
files instead of being buried in a script.

| | root | shell |
|---|---|---|
| target path | `/data/adb/openar` | `/data/local/tmp/openar` |
| interfaces | `usb0 swlan0` | `lo` |
| port | 80 | 8080 |
| kernel log | written | skipped |
| reboot durability | external (Magisk service / boot hook) | none |

Add a platform when a new environment appears (e.g. a non-Magisk root); keep the runtime
detection in `core/lib/openar-platform.sh` and the defaults here in sync.
