#!/usr/bin/env bash
# Process lifecycle shared by review.sh and agent.sh: a command in its own session that outlives
# the call that starts it, waited on in short calls, stopped only after an identity check.
# Source it (`. proc.sh`); it defines functions only and changes no shell options.
# Usage:
#   proc_canon <path>            print <path> with its directory resolved (pwd -P)
#   proc_host                    print the nearest claude or codex process name above this shell, or none
#   proc_start <out> <cmd...>    fork, setsid, run <cmd> with this call's stdin (redirect it from a
#                                file), stdout and stderr to <out>; writes <out>.pid and, when <cmd>
#                                ends, <out>.exit; prints the pid. Refused (return 1, nothing
#                                overwritten) while the run recorded for <out> is alive (or alive and
#                                unverifiable), or while another start for <out> holds <out>.starting
#   proc_wait <out> [secs] [limit]
#                                wait up to <secs> (default 50) for the run to end; return 0
#                                "ended exit <code>", 3 "running", 1 "ended lost" (no exit code and
#                                no live process of this run on record) or "ended timeout" (over
#                                <limit> seconds since start, default 1200; its process group is
#                                stopped, or the line says it is still running or was not stopped)
#   proc_peek <out>              look once, never signal: 0 "ended exit <code>", 3 "running", 1 "ended lost"
#   proc_stop <out>              stop the run's process group after the identity check and confirm it
#                                is gone: return 0 "ok stopped" / "ok not running", or 1
#                                "not stopped: <reason>" (nothing is signalled when the check fails)
# <out>.pid: line 1 "<pid> <started>", then "lstart: <ps lstart>" and "command: <ps command>" of the
# wrapper (`python3 -I - <out> ...`), read right after the fork. Identity: the pid leads its own
# process group and its lstart and command equal the recorded ones exactly. A record without them
# (older format) is not this run. Without ps (some sandboxes refuse it) identity cannot be checked:
# a live pid counts as running, a timeout is only reported, and nothing is ever signalled.
# Times are wall-clock seconds.

proc_host() {
    local p=$PPID c i=0
    while [ "${p:-0}" -gt 1 ] && [ $i -lt 40 ]; do
        c=$(basename "$(ps -o comm= -p "$p" 2>/dev/null)" 2>/dev/null)
        case $c in claude|codex) echo "$c"; return ;; esac
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i + 1))
    done
    echo none
}
proc_canon() { echo "$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")"; }

_proc_ps() { # <field> <pid>: one ps field, tabs and newlines as spaces, outer spaces trimmed (as the wrapper records it)
    ps -ww -o "$1=" -p "$2" 2>/dev/null | tr '\n\t' '  ' | sed 's/^ *//; s/ *$//'
}
_proc_load() { # sets _pp _ps _pl _pc (pid, started, lstart, command) from <out>.pid; _pp empty when missing or malformed
    _pp=""; _ps=""; _pl=""; _pc=""
    if [ -f "$1.pid" ]; then
        read -r _pp _ps < "$1.pid" 2>/dev/null
        _pl=$(sed -n 's/^lstart: //p' "$1.pid" | head -1); _pc=$(sed -n 's/^command: //p' "$1.pid" | head -1)
    fi
    case "$_pp:$_ps" in *[!0-9:]*|:*|*:) _pp=""; _ps="" ;; esac
    _canps=1; ps -o pid= -p $$ >/dev/null 2>&1 || _canps=0
}
_proc_id() { # 0 the recorded pid is this run, 1 it is not (or is gone), 2 alive but cannot be checked (no ps)
    [ -n "$_pp" ] && kill -0 "$_pp" 2>/dev/null || return 1
    [ $_canps = 1 ] || return 2
    [ -n "$_pl" ] && [ -n "$_pc" ] || return 1
    [ "$(ps -o pgid= -p "$_pp" 2>/dev/null | tr -d ' ')" = "$_pp" ] || return 1
    [ "$(_proc_ps lstart "$_pp")" = "$_pl" ] && [ "$(_proc_ps command "$_pp")" = "$_pc" ]
}
_proc_group() { kill -0 -- -"$_pp" 2>/dev/null; }  # any process of the group left
_proc_kill() { # TERM the group, then KILL; return 0 when the group is gone
    kill -TERM -- -"$_pp" 2>/dev/null
    for _ in 1 2 3 4 5; do _proc_group || break; sleep 1; done
    _proc_group && { kill -KILL -- -"$_pp" 2>/dev/null; sleep 1; }
    ! _proc_group
}

proc_start() {
    local out rc; out=$(proc_canon "$1"); shift
    [ $# -gt 0 ] || { echo "proc_start: no command" >&2; return 2; }
    # one start at a time per <out>: the loser of this mkdir touches nothing
    mkdir "$out.starting" 2>/dev/null || { echo "FAIL another start of $out is in progress ($out.starting; remove it only if no start is running)" >&2; return 1; }
    _proc_load "$out"
    if [ ! -f "$out.exit" ]; then
        _proc_id; rc=$?
        [ $rc = 1 ] || { rmdir "$out.starting"; echo "FAIL $out is still running as pid $_pp; not started again" >&2; return 1; }
    fi
    rm -f "$out.exit" "$out.pid"
    python3 -I - "$out" "$@" 3<&0 <<'PY'
import os, subprocess, sys, time
out, cmd = sys.argv[1], sys.argv[2:]
def ps(field, pid):  # as _proc_ps prints it
    try:
        r = subprocess.run(["ps", "-ww", "-o", field + "=", "-p", str(pid)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return ""
    if r.returncode != 0:
        return ""
    return r.stdout.decode(errors="replace").replace("\n", " ").replace("\t", " ").strip(" ")
started = int(time.time())
pid = os.fork()
if pid:
    with open(out + ".pid.tmp", "w") as f:
        f.write("%d %d\nlstart: %s\ncommand: %s\n" % (pid, started, ps("lstart", pid), ps("command", pid)))
    os.rename(out + ".pid.tmp", out + ".pid")
    print(pid)
    sys.exit(0)
os.setsid()  # its own session: the host's end-of-call cleanup does not reach it
null = os.open(os.devnull, os.O_RDWR)
os.dup2(3, 4)  # the caller's stdin (fd 3), kept for the command
os.close(3)
for fd in (0, 1, 2):
    os.dup2(null, fd)  # release the caller's pipes so the call returns now
with open(out, "wb") as o:
    try:
        r = subprocess.call(cmd, stdin=4, stdout=o, stderr=subprocess.STDOUT)
    except OSError as e:
        o.write(("cannot start %s: %s\n" % (cmd[0], e)).encode())
        r = 127
with open(out + ".exit", "w") as f:
    f.write("%d\n" % r)
PY
    rc=$?; rmdir "$out.starting"; return $rc
}

proc_wait() {
    local out secs=${2:-50} limit=${3:-1200} end id
    out=$(proc_canon "$1"); _proc_load "$out"
    end=$(( $(date +%s) + secs ))
    while [ ! -f "$out.exit" ] && [ "$(date +%s)" -lt "$end" ]; do
        _proc_id; [ $? = 1 ] && break
        [ $(( $(date +%s) - _ps )) -lt "$limit" ] || break
        sleep 2
    done
    if [ -f "$out.exit" ]; then echo "ended exit $(cat "$out.exit")"; return 0; fi
    _proc_id; id=$?
    [ $id != 1 ] || { echo "ended lost"; return 1; }
    if [ $(( $(date +%s) - _ps )) -ge "$limit" ]; then
        [ $id = 0 ] || { echo "ended timeout, not stopped: cannot check that $_pp is this run"; return 1; }
        if _proc_kill; then echo "ended timeout"; else echo "ended timeout, still running $_pp"; fi
        return 1
    fi
    echo "running"; return 3
}

proc_peek() {
    local out; out=$(proc_canon "$1"); _proc_load "$out"
    if [ -f "$out.exit" ]; then echo "ended exit $(cat "$out.exit")"; return 0; fi
    _proc_id; [ $? = 1 ] && { echo "ended lost"; return 1; }
    echo "running"; return 3
}

proc_stop() {
    local out id; out=$(proc_canon "$1"); _proc_load "$out"
    [ -n "$_pp" ] || { echo "not stopped: no pid record at $out.pid"; return 1; }
    if ! kill -0 "$_pp" 2>/dev/null; then
        _proc_group && { echo "not stopped: leader $_pp is gone but its process group still runs"; return 1; }
        echo "ok not running"; return 0
    fi
    _proc_id; id=$?
    [ $id != 2 ] || { echo "not stopped: cannot check that $_pp is this run (no ps)"; return 1; }
    [ $id = 0 ] || { echo "not stopped: pid $_pp is not this run (identity check failed)"; return 1; }
    if _proc_kill; then echo "ok stopped"; return 0; fi
    echo "not stopped: still running $_pp"; return 1
}
