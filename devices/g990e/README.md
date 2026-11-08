# devices/g990e -- Galaxy S21 FE (SM-G990E, `ro.product.device=r9s`)

A reference device pack: everything that differs from `core/` for this phone.

- `etc/status.d/20-battery`: core block plus Samsung's `protect_battery` charge limit.
- Add `etc/web.conf` / `etc/commands` here when this phone needs different interfaces, ports or
  commands from the defaults.

Build and deploy with:

```sh
tools/deploy.sh <serial> --pack g990e --root
tools/check.sh  <serial> --mode root
```

Pack names are device model identifiers, not brands: `g990e`, `g970w`, `sg701sh`.
