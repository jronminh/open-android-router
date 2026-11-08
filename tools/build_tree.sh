#!/bin/sh
# build_tree.sh <pack> [outdir] -- materialise the runnable tree: core/ plus devices/<pack>/.
# The result is a plain directory (bin/ lib/ etc/ var/ home/) that deploy.sh pushes as-is.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pack=${1:-generic}
out=${2:-$here/out/$pack}
rm -rf "$out"
mkdir -p "$out"
cp -a "$here/core/." "$out/"
if [ -d "$here/devices/$pack" ]; then
    for d in etc bin lib; do
        if [ -d "$here/devices/$pack/$d" ]; then
            mkdir -p "$out/$d"
            cp -a "$here/devices/$pack/$d/." "$out/$d/"
        fi
    done
fi
mkdir -p "$out/var/log" "$out/var/run" "$out/var/tmp" "$out/home"
ver="0.1"
if git -C "$here" rev-parse --short HEAD >/dev/null 2>&1; then
    ver="$ver+$(git -C "$here" rev-parse --short HEAD)"
    if ! git -C "$here" diff --quiet 2>/dev/null; then ver="$ver-dirty"; fi
fi
echo "$ver" > "$out/VERSION"
echo "$out"
