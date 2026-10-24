#!/usr/bin/env bash
# Process lifecycle shared by review.sh and agent.sh: a command in its own session that outlives
# the call that starts it, waited on in short calls, stopped only after an identity check.
# Source it (`. proc.sh`); it defines functions only and changes no shell options.
# Usage:
#   proc_canon <path>            print <path> with its directory resolved (pwd -P)
#   proc_host                    print the nearest claude or codex process name above this shell, or none
#   proc_start <out> <cmd...>    fork, setsid, run <cmd> with this call's stdin (redirect it from a
#                                file), stdout and stderr to <out>; writes <out>.pid ("pid started")
#                                and, when <cmd> ends, <out>.exit; prints the pid. Refused (return 1,
#                                nothing overwritten) while the run recorded for <out> is still alive
#   proc_wait <out> [secs] [limit]
#                                wait up to <secs> (default 50) for the run to end; return 0
#                                "ended exit <code>", 3 "running", 1 "ended lost" (no exit code and
#                                no live process of this run on record) or "ended timeout" (over
#                                <limit> seconds since start, default 1200; its process group is
#                                stopped, or the line says it is still running or was not stopped)
#   proc_stop <out>              stop the run's process group after the identity check and confirm it
#                                is gone: return 0 "ok stopped" / "ok not running", or 1
#                                "not stopped: <reason>" (nothing is signalled when the check fails)
# Identity: the recorded pid leads its own process group and its command names <out> (the wrapper
# runs as `python3 -I - <out> ...`). Without ps (some sandboxes refuse it) a live pid counts as this
# run for waiting, and nothing is ever signalled. Times are wall-clock seconds.

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

_proc_load() { # sets _pp _ps (pid, started) from <out>.pid, empty when missing or old format
    _pp=""; _ps=""
    [ -f "$1.pid" ] && read -r _pp _ps < "$1.pid" 2>/dev/null
    case "$_pp:$_ps" in *[!0-9:]*|:*|*:) _pp=""; _ps="" ;; esac
    _canps=1; ps -o pid= -p $$ >/dev/null 2>&1 || _canps=0
}
_proc_mine() { # <out>: the recorded pid still leads this run's process group (without ps: is alive)
    [ -n "$_pp" ] || return 1
    [ $_canps = 1 ] || { kill -0 "$_pp" 2>/dev/null; return; }
    [ "$(ps -o pgid= -p "$_pp" 2>/dev/null | tr -d ' ')" = "$_pp" ] &&
        ps -ww -o command= -p "$_pp" 2>/dev/null | grep -qF -- "$1"
}
_proc_group() { kill -0 -- -"$_pp" 2>/dev/null; }  # any process of the group left
_proc_kill() { # TERM the group, then KILL; return 0 when the group is gone
    kill -TERM -- -"$_pp" 2>/dev/null
    for _ in 1 2 3 4 5; do _proc_group || break; sleep 1; done
    _proc_group && { kill -KILL -- -"$_pp" 2>/dev/null; sleep 1; }
    ! _proc_group
}

proc_start() {
    local out; out=$(proc_canon "$1"); shift
    [ $# -gt 0 ] || { echo "proc_start: no command" >&2; return 2; }
    _proc_load "$out"
    if [ ! -f "$out.exit" ] && _proc_mine "$out"; then
        echo "FAIL $out is still running as pid $_pp; not started again" >&2; return 1
    fi
    rm -f "$out.exit" "$out.pid"
    python3 -I - "$out" "$@" 3<&0 <<'PY'
import os, subprocess, sys, time
out, cmd = sys.argv[1], sys.argv[2:]
pid = os.fork()
if pid:
    with open(out + ".pid", "w") as f:
        f.write("%d %d\n" % (pid, int(time.time())))  # for wait: pid and start time
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
}

proc_wait() {
    local out secs=${2:-50} limit=${3:-1200} end
    out=$(proc_canon "$1"); _proc_load "$out"
    end=$(( $(date +%s) + secs ))
    while [ ! -f "$out.exit" ] && [ "$(date +%s)" -lt "$end" ]; do
        _proc_mine "$out" || break
        [ $(( $(date +%s) - _ps )) -lt "$limit" ] || break
        sleep 2
    done
    if [ -f "$out.exit" ]; then echo "ended exit $(cat "$out.exit")"; return 0; fi
    _proc_mine "$out" || { echo "ended lost"; return 1; }
    if [ $(( $(date +%s) - _ps )) -ge "$limit" ]; then
        [ $_canps = 1 ] || { echo "ended timeout, not stopped: cannot check that $_pp is this run"; return 1; }
        if _proc_kill; then echo "ended timeout"; else echo "ended timeout, still running $_pp"; fi
        return 1
    fi
    echo "running"; return 3
}

proc_stop() {
    local out; out=$(proc_canon "$1"); _proc_load "$out"
    [ -n "$_pp" ] || { echo "not stopped: no pid record at $out.pid"; return 1; }
    if ! kill -0 "$_pp" 2>/dev/null; then
        _proc_group && { echo "not stopped: leader $_pp is gone but its process group still runs"; return 1; }
        echo "ok not running"; return 0
    fi
    [ $_canps = 1 ] || { echo "not stopped: cannot check that $_pp is this run (no ps)"; return 1; }
    _proc_mine "$out" || { echo "not stopped: pid $_pp is not this run (identity check failed)"; return 1; }
    if _proc_kill; then echo "ok stopped"; return 0; fi
    echo "not stopped: still running $_pp"; return 1
}
