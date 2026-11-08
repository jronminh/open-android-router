#!/system/bin/sh
# openar-commands.sh -- the command list: etc/commands (owner copy) else etc/commands.default.
#
# Model: luci-app-commands -- stdout, stderr, exit code, output cap, the parameter appended as one
# quoted word -- plus a per-command regex, a timeout, and a log line for every "act" run.
# Refusing is part of the contract: an unknown id, a group that is not allowed in this zone, a
# missing parameter or one that does not match the regex all return 2 with r_err set.
#
# Sets: CMDS (the file in use), CAP, TAB. Functions: cmd_list, cmd_get, cmd_run.
# cmd_get: c_id c_section c_group c_confirm c_timeout c_regex c_desc c_cmd
# cmd_run: r_out r_err r_rc r_cmdline

CMDS=$OPENAR_ROOT/etc/commands; [ -f "$CMDS" ] || CMDS=$OPENAR_ROOT/etc/commands.default
TAB=$(printf '\t')
CAP=524288

cmd_list() { grep -v '^#' "$CMDS" 2>/dev/null | grep "$TAB"; }

cmd_get() {
    line=$(cmd_list | awk -F'\t' -v id="$1" '$1 == id' | head -1)
    [ -n "$line" ] || return 1
    IFS="$TAB" read -r c_id c_section c_group c_confirm c_timeout c_regex c_desc c_cmd <<EOF
$line
EOF
    return 0
}

# zone "view" runs read-only commands (auto|view); zone "act" runs act only; "any" is ADB.
group_ok() {
    case "$2:$1" in view:auto|view:view|act:act) return 0 ;; *) return 1 ;; esac
}

quote_arg() { printf "'%s'" "$(print -nr -- "$1" | sed "s/'/'\\\\''/g")"; }

cmd_run() {
    cmd_get "$1" || { r_err="no such command: $1"; return 2; }
    [ "$2" = any ] || group_ok "$c_group" "$2" || { r_err="command $1 belongs to group $c_group, not runnable here"; return 2; }
    arg=""
    if [ -n "${3:-}" ]; then
        [ "$c_regex" != "-" ] || { r_err="command $1 takes no parameter"; return 2; }
        print -nr -- "$3" | grep -Eqx "$c_regex" || { r_err="parameter does not match $c_regex"; return 2; }
        arg=" $(quote_arg "$3")"
    elif [ "$c_regex" != "-" ]; then
        r_err="command $1 needs a parameter ($c_regex)"; return 2
    fi
    r_cmdline="$c_cmd$arg"
    o=$(mktemp "$OPENAR_ROOT/tmp/cmd.XXXXXX") e=$(mktemp "$OPENAR_ROOT/tmp/cmd.XXXXXX")
    [ -n "$o" ] && [ -n "$e" ] || { r_err="cannot create temporary files in $OPENAR_ROOT/tmp"; return 2; }
    # stdout/stderr go through PIPES, never straight into files under the app's data dir:
    # "cmd"/"settings" pass their fds to system_server over binder and SELinux denies
    # system_server our files (adb_data_file -> "Failed transaction"); pipes are fine.
    set -o pipefail
    ( PATH=$OPENAR_ROOT/bin:/system/bin:/system/xbin timeout "$c_timeout" sh -c "$r_cmdline" 2>&1 1>&3 3>&- | cat > "$e" ) 3>&1 | cat > "$o"
    r_rc=$?
    set +o pipefail
    r_out=$(head -c $CAP "$o"); r_err=$(head -c $CAP "$e"); rm -f "$o" "$e"
    [ "$r_rc" = 124 ] && r_err="$r_err
(timed out after ${c_timeout}s)"
    if [ "$c_group" = act ]; then
        echo "$(date '+%F %T') run $1${3:+ $3} exit=$r_rc by=${REMOTE_USER:-adb} from=${REMOTE_ADDR:-local}" >> "$OPENAR_ROOT/var/log/actions.log"
        olog "run $1${3:+ $3} exit=$r_rc"
    fi
    return 0
}
