#!/bin/sh
# deploy.sh <serial> [--root|--shell] [--pack generic] [--ifaces "..."] [--port N] [--busybox PATH]
#
# Builds the tree, pushes it, keeps the owner's config (etc/httpd.conf, etc/commands, etc/web.conf)
# and var/ across deploys, then creates bin/shims: the busybox symlink farm that gives one POSIX
# behaviour on every Android version (see docs/ARCHITECTURE.md "Busybox first").
#   root  -> /data/adb/openar       (installed over su, :80 by default; Magisk only)
#   shell -> /data/local/tmp/openar (:8080 by default, loopback only)
# busybox is not shipped in this repo (GPL). --busybox points at a local static binary; otherwise
# a busybox already on the device is used.
set -eu
# Git Bash on Windows: adb.exe must receive /data/... literally.
[ -n "${MSYSTEM:-}" ] && export MSYS_NO_PATHCONV=1
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
serial=${1:-}
[ -n "$serial" ] || { echo "usage: deploy.sh <serial> [--root|--shell] [--pack generic] [--ifaces ...] [--port N] [--busybox PATH]" >&2; exit 64; }
shift
mode=""; pack="generic"; ifaces=""; port=""; busybox=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) mode=root ;;
        --shell) mode=shell ;;
        --pack) pack=$2; shift ;;
        --ifaces) ifaces=$2; shift ;;
        --port) port=$2; shift ;;
        --busybox) busybox=$2; shift ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done
if [ -z "$mode" ]; then
    if [ "$(adb -s "$serial" shell id -u | tr -d '\r')" = 0 ]; then mode=root; else mode=shell; fi
fi
if [ "$mode" = root ]; then target=/data/adb/openar; else target=/data/local/tmp/openar; fi
. "$here/platform/$mode/defaults.sh"
[ -n "$port" ] || port=$OPENAR_PORT
[ -n "$ifaces" ] || ifaces=$OPENAR_IFACES

# POSIX tools busybox must provide. Android framework commands are NOT in here on purpose.
SHIMS="awk base64 cat cut date df dirname egrep fgrep find grep head ip mktemp mkdir mv printf readlink realpath rm sed seq sha256sum sleep sort stat tail tar timeout top touch tr uniq wc xargs gzip"

out=$(sh "$here/tools/build_tree.sh" "$pack")
out_adb=$out
if command -v cygpath >/dev/null 2>&1; then out_adb=$(cygpath -m "$out"); fi
echo "deploy: pack=$pack mode=$mode target=$target port=$port ifaces=$ifaces"

if [ "$mode" = shell ]; then
    adb -s "$serial" shell "rm -rf $target.tmp; mkdir -p $target.tmp"
    adb -s "$serial" push "$out_adb/." "$target.tmp/" >/dev/null
    if [ -n "$busybox" ]; then
        bb_adb=$busybox; command -v cygpath >/dev/null 2>&1 && bb_adb=$(cygpath -m "$busybox")
        adb -s "$serial" push "$bb_adb" "$target.tmp/bin/busybox" >/dev/null
        echo "openar: busybox from --busybox"
    fi
    adb -s "$serial" shell "cd $target.tmp || exit 1
for f in etc/httpd.conf etc/commands etc/web.conf bin/busybox; do [ -f $target/\$f ] && cp -a $target/\$f \$f; done
if [ -d $target/var ]; then rm -rf var; cp -a $target/var .; fi
chmod 755 bin/* 2>/dev/null
chmod 755 etc/www/cgi-bin/*/*.cgi 2>/dev/null
[ -f etc/httpd.conf ] || { cp etc/httpd.conf.example etc/httpd.conf; echo 'openar: created etc/httpd.conf from the example -- change the password'; }
chmod 600 etc/httpd.conf
[ -f etc/web.conf ] || printf 'ifaces=\"%s\"\nport=%s\n' '$ifaces' '$port' > etc/web.conf
if [ ! -x bin/busybox ]; then
  for p in $OPENAR_BUSYBOX_SEARCH; do
    if [ -x \$p ]; then cp \$p bin/busybox; echo \"openar: busybox from \$p\"; break; fi
  done
fi
[ -x bin/busybox ] || echo 'openar: WARNING no busybox found; pass --busybox PATH or put one at bin/busybox'
if [ -x bin/busybox ]; then
  mkdir -p bin/shims
  for a in $SHIMS; do ln -sf ../busybox bin/shims/\$a; done
fi"
    adb -s "$serial" shell "rm -rf $target.old; if [ -d $target ]; then mv $target $target.old; fi; mv $target.tmp $target; rm -rf $target.old"
else
    tmpd=$(mktemp -d)
    tmpd_adb=$(cygpath -m "$tmpd" 2>/dev/null || echo "$tmpd")
    tar czf "$tmpd/openar.tgz" -C "$out" .
    [ -n "$busybox" ] && cp "$busybox" "$tmpd/openar-busybox"
    cat > "$tmpd/install.sh" <<EOF
#!/system/bin/sh
set -u
T=$target
rm -rf \$T.new
mkdir -p \$T.new
tar xzf /data/local/tmp/openar.tgz -C \$T.new || exit 1
for f in etc/httpd.conf etc/commands etc/web.conf bin/busybox; do
    [ -f \$T/\$f ] && cp -a \$T/\$f \$T.new/\$f
done
[ -d \$T/var ] && { rm -rf \$T.new/var; cp -a \$T/var \$T.new/var; }
mkdir -p \$T.new/var/log \$T.new/var/run \$T.new/var/tmp \$T.new/home
chmod 755 \$T.new/bin/* 2>/dev/null
chmod 755 \$T.new/etc/www/cgi-bin/*/*.cgi 2>/dev/null
[ -f \$T.new/etc/httpd.conf ] || { cp \$T.new/etc/httpd.conf.example \$T.new/etc/httpd.conf; echo 'openar: created etc/httpd.conf from the example -- change the password'; }
chmod 600 \$T.new/etc/httpd.conf
[ -f \$T.new/etc/web.conf ] || printf 'ifaces="%s"\nport=%s\n' '$ifaces' '$port' > \$T.new/etc/web.conf
if [ -f /data/local/tmp/openar-busybox ]; then
    cp /data/local/tmp/openar-busybox \$T.new/bin/busybox; rm -f /data/local/tmp/openar-busybox
    echo "openar: busybox from --busybox"
elif [ ! -x \$T.new/bin/busybox ]; then
    for p in $OPENAR_BUSYBOX_SEARCH; do
        if [ -x \$p ]; then cp \$p \$T.new/bin/busybox; echo "openar: busybox from \$p"; break; fi
    done
fi
if [ -x \$T.new/bin/busybox ]; then
    mkdir -p \$T.new/bin/shims
    cd \$T.new || exit 1
    for a in $SHIMS; do ln -sf ../busybox bin/shims/\$a; done
fi
chown -R 0:0 \$T.new 2>/dev/null
chmod 700 \$T.new
rm -rf \$T.old
[ -d \$T ] && mv \$T \$T.old
mv \$T.new \$T
rm -rf \$T.old
echo "openar: installed to \$T"
EOF
    adb -s "$serial" push "$tmpd_adb/openar.tgz" /data/local/tmp/openar.tgz >/dev/null
    adb -s "$serial" push "$tmpd_adb/install.sh" /data/local/tmp/openar-install.sh >/dev/null
    adb -s "$serial" shell "su -c 'sh /data/local/tmp/openar-install.sh'"
    adb -s "$serial" shell "rm -f /data/local/tmp/openar.tgz /data/local/tmp/openar-install.sh" || true
    rm -rf "$tmpd"
fi

# Verify the applet set once, on the host: the shims are only as good as the busybox behind them.
if [ "$mode" = root ]; then
    bb_list=$(adb -s "$serial" shell "su -c '$target/bin/busybox --list'" 2>/dev/null || true)
else
    bb_list=$(adb -s "$serial" shell "$target/bin/busybox --list" 2>/dev/null || true)
fi
bb_list=$(printf '%s' "$bb_list" | tr -d '\r' | tr '\n' ' ')
miss=""
for a in $SHIMS; do
    case " $bb_list " in *" $a "*) ;; *) miss="$miss $a" ;; esac
done
if [ -n "$miss" ]; then
    echo "openar: WARNING busybox is missing applets:$miss (the shims on those names will fail)"
else
    echo "openar: busybox applets OK ($(echo $SHIMS | wc -w) shims)"
fi

echo
echo "next:"
if [ "$mode" = root ]; then
    echo "  adb -s $serial shell \"su -c '$target/bin/openar-web start'\""
    echo "  open http://<usb0 IP>:$port/   (credentials in $target/etc/httpd.conf)"
else
    echo "  adb -s $serial shell $target/bin/openar-web start"
    echo "  adb -s $serial forward tcp:8080 tcp:$port"
    echo "  open http://127.0.0.1:8080/"
fi
