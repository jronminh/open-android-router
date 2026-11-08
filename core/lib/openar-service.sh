#!/system/bin/sh
# openar-service.sh -- verb dispatch for openar-<name> services (the OpenWrt rc.common idea).
# A service sets VERBS="..." and one svc_<verb> function per verb, sources this file and calls
# openar_dispatch "$@". Read-only verbs (status, check) may be shown on the web; act verbs run only
# through the act zone. Intent files live in etc/ (there is no ramdisk on the rootless floor).
VERBS=${VERBS:-}
kv() { print -r -- "$1=$2"; }
say() { echo "${0##*/}: $*"; olog "${0##*/}: $*"; }
intent() { echo "$OPENAR_ROOT/etc/$1"; }
openar_dispatch() {
    v=${1:-}
    case " $VERBS verbs " in
        *" $v "*) ;;
        *) echo "usage: ${0##*/} $(echo $VERBS verbs | tr ' ' '|')" >&2; exit 64 ;;
    esac
    [ "$v" = verbs ] && { echo "$VERBS"; exit 0; }
    shift
    "svc_$(echo "$v" | tr - _)" "$@"
}
