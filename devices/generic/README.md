# Device packs

A device pack is a directory whose `etc/`, `bin/` and `lib/` overlay the tree built from
`core/`. Use it for what is specific to one phone:

- `etc/web.conf` -- which interfaces to serve and the port.
- `etc/httpd.conf` -- never commit a real password here; the deploy script creates it on the
  device from the example if missing. Ship only the example if you need a different user.
- `etc/commands` -- a device-specific command list (overrides `commands.default` entirely;
  copy the default first and edit).
- `etc/status.d/` -- extra or replaced status blocks.
- `bin/` -- extra commands, e.g. hardware-specific helpers.

Nothing here is loaded unless you build/deploy with `--pack <name>`.
