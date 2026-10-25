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
#                                overwritten) while the run recorded for <out> is alive (or its pid is
#                                alive and its identity unknown), while <out>.timeout is there (no .exit)
#                                and the recorded process group still has a member or cannot be checked
#                                (its leader gone or not), or while another start for <out>
#                                holds <out>.starting. DFLOW_PROC_LIMIT=<seconds>: the session leader
#                                (the forked wrapper) keeps that deadline itself, with or without
#                                proc_wait: past it, it ignores TERM, TERMs its process group, waits up
#                                to 5s, KILLs each other member still there and polls (up to 10s more)
#                                until the group holds only itself; then it appends "timeout after <N>s"
#                                to <out>, writes 124 to <out>.exit and exits. Members still left at the
#                                end: it writes <out>.timeout "timeout after <N>s, not stopped: <pids>",
#                                no .exit, and stays alive (proc_stop stops it). Unset: no deadline of
#                                its own. The command gets
#                                DFLOW_HOLDER_PID=<the leader's pid> (the recorded pid), not the limit
#   proc_wait <out> [secs] [limit]
#                                wait up to <secs> (default 50) for the run to end; return 0
#                                "ended exit <code>", 3 "running", "running (identity unverified)" or
#                                "running (timeout, not stopped)" (<out>.timeout, no <out>.exit, leader not gone),
#                                1 "ended lost" (no exit code, and the recorded pid is gone or is
#                                provably another process), "ended timeout, stopped late" (as lost, but
#                                with <out>.timeout and the process group provably empty; while the group
#                                still has a member or cannot be checked, the leader gone or not, it is
#                                "running (timeout, not stopped)") or "ended timeout" (over <limit> seconds
#                                since start, default 1200; its process group is stopped, or the line
#                                says it is still running or was not stopped)
#   proc_peek <out>              look once, never signal: 0 "ended exit <code>", 3 "running",
#                                "running (identity unverified)" or "running (timeout, not stopped)",
#                                1 "ended lost" or "ended timeout, stopped late" (as proc_wait)
#   proc_stop <out>              stop the run's process group after the identity check and confirm it
#                                is gone: return 0 "ok stopped" / "ok not running", or 1
#                                "not stopped: <reason>" (nothing is signalled when the check fails).
#                                Success only once the process group is provably empty (kill -0 on it
#                                says "No such process"); a group that cannot be checked (e.g. not
#                                permitted) is "not stopped: cannot check the process group <pgid>".
#                                Leader gone: "not stopped" while its group has a member or cannot be
#                                checked; once the group is provably empty "ok not running". A confirmed
#                                stop keeps <out>.timeout (a line "stopped" is appended), so wait and
#                                peek still say "ended timeout, stopped late"
# <out>.pid: line 1 "<pid> <started>", then "lstart: <ps lstart>" and "command: <ps command>" of the
# wrapper (`python3 -I - <out> ...`), read right after the fork. Identity: the pid leads its own
# process group and its lstart and command equal the recorded ones exactly. The identity is unknown
# when the pid is alive but cannot be checked: no ps (some sandboxes refuse it), ps fails for that
# pid, or the record lacks lstart or command (an older format, or a start without ps). An unknown
# identity counts as running ("running (identity unverified)"): never restarted over, never reported
# lost, never signalled, and a timeout is only reported. Only a pid that is gone (kill -0 fails) or
# whose pgid, lstart or command differs from the record is not this run.
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
_proc_id() { # 0 the recorded pid is this run, 1 it is gone or provably another process, 2 alive but unknown
    local g l c
    [ -n "$_pp" ] && kill -0 "$_pp" 2>/dev/null || return 1
    [ $_canps = 1 ] && [ -n "$_pl" ] && [ -n "$_pc" ] || return 2
    g=$(ps -o pgid= -p "$_pp" 2>/dev/null | tr -d ' '); l=$(_proc_ps lstart "$_pp"); c=$(_proc_ps command "$_pp")
    # a field ps did answer and that differs from the record is proof; a field it did not answer is not
    { [ -n "$g" ] && [ "$g" != "$_pp" ]; } || { [ -n "$l" ] && [ "$l" != "$_pl" ]; } || { [ -n "$c" ] && [ "$c" != "$_pc" ]; } && return 1
    [ -n "$g" ] && [ -n "$l" ] && [ -n "$c" ] && return 0
    kill -0 "$_pp" 2>/dev/null && return 2   # ps could not answer for a live pid
    return 1
}
_proc_gstate() { # 0 the recorded group still has a member, 1 it is provably empty, 2 cannot tell
    local e
    [ -n "$_pp" ] || return 2
    e=$(kill -0 -- -"$_pp" 2>&1) && return 0
    case $e in *"No such process"*) return 1 ;; esac
    return 2   # e.g. not permitted: there is a member, or kill cannot say
}
_proc_late() { # <out>, its leader gone: with <out>.timeout (a stop that was not confirmed), say what the group is
    # prints and returns as wait/peek: 3 "running (timeout, not stopped)" while a member is left or it
    # cannot be told; 1 "ended timeout, stopped late" once the group is provably empty. No .timeout: 1 "ended lost"
    [ -f "$1.timeout" ] || { echo "ended lost"; return 1; }
    _proc_gstate; case $? in
    1) echo "ended timeout, stopped late"; return 1 ;;
    *) echo "running (timeout, not stopped)"; return 3 ;;
    esac
}
_proc_kill() { # TERM the group, then KILL; return as _proc_gstate after it: 1 the group is provably
    # empty (stopped), 0 a member is still there, 2 it cannot be checked (never taken as stopped)
    local g
    kill -TERM -- -"$_pp" 2>/dev/null
    for _ in 1 2 3 4 5; do _proc_gstate; g=$?; [ $g = 0 ] || break; sleep 1; done
    if [ $g != 1 ]; then kill -KILL -- -"$_pp" 2>/dev/null; sleep 1; fi
    _proc_gstate
}
_proc_stopped() { # <out>: a confirmed stop keeps <out>.timeout (the run's end stays "timeout, stopped late") and notes it
    [ ! -f "$1.timeout" ] || grep -qx stopped "$1.timeout" 2>/dev/null || echo stopped >> "$1.timeout"
}

proc_start() {
    local out rc; out=$(proc_canon "$1"); shift
    [ $# -gt 0 ] || { echo "proc_start: no command" >&2; return 2; }
    [ -z "${DFLOW_PROC_LIMIT:-}" ] || printf '%s' "$DFLOW_PROC_LIMIT" | grep -Eq '^[1-9][0-9]{0,6}$' ||
        { echo "proc_start: DFLOW_PROC_LIMIT must be a whole number of seconds: $DFLOW_PROC_LIMIT" >&2; return 2; }
    # one start at a time per <out>: the loser of this mkdir touches nothing
    mkdir "$out.starting" 2>/dev/null || { echo "FAIL another start of $out is in progress ($out.starting; remove it only if no start is running)" >&2; return 1; }
    _proc_load "$out"
    if [ ! -f "$out.exit" ]; then
        _proc_id; rc=$?
        [ $rc != 0 ] || { rmdir "$out.starting"; echo "FAIL $out is still running as pid $_pp; not started again" >&2; return 1; }
        [ $rc != 2 ] || { rmdir "$out.starting"; echo "FAIL $out: pid $_pp is alive and cannot be checked as this run (identity unverified); not started again, nothing overwritten" >&2; return 1; }
        # its leader is gone, but a timeout stop was never confirmed: only a provably empty group is over
        if [ -f "$out.timeout" ]; then
            _proc_gstate; rc=$?
            [ $rc = 1 ] || { rmdir "$out.starting"; echo "FAIL $out: timed out and its process group $_pp $([ $rc = 0 ] && echo "still has a member" || echo "cannot be checked") (leader gone, stop not confirmed: $out.timeout); not started again, nothing overwritten" >&2; return 1; }
        fi
    fi
    rm -f "$out.exit" "$out.pid" "$out.timeout"
    DFLOW_PROC_LIMIT="${DFLOW_PROC_LIMIT:-}" python3 -I - "$out" "$@" 3<&0 <<'PY'
import os, signal, subprocess, sys, time
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
limit = os.environ.pop("DFLOW_PROC_LIMIT", "")
os.environ["DFLOW_HOLDER_PID"] = str(os.getpid())  # this leader: lives as long as the run
p = None
with open(out, "wb") as o:
    try:
        p = subprocess.Popen(cmd, stdin=4, stdout=o, stderr=subprocess.STDOUT)
    except OSError as e:
        o.write(("cannot start %s: %s\n" % (cmd[0], e)).encode())
        r = 127
if p is not None:
    try:
        r = p.wait(timeout=int(limit) if limit else None)
    except subprocess.TimeoutExpired:  # the deadline is kept here, whether or not anyone calls proc_wait
        # .exit is written only once the group holds nothing but this leader
        me = os.getpid()
        def others():
            p.poll()  # reap the command, so it does not linger as a zombie of this leader
            try:
                q = subprocess.Popen(["ps", "-A", "-o", "pid=,ppid=,pgid=,stat="], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                text = q.communicate()[0]
            except OSError:
                return None
            if q.returncode != 0:
                return None
            left = []
            for line in text.decode(errors="replace").splitlines():
                f = line.split()  # this ps (and what it runs) is a member too, and not the run's
                if len(f) >= 4 and f[2] == str(me) and f[0] not in (str(me), str(q.pid)) and f[1] != str(q.pid) and not f[3].startswith("Z"):
                    left.append(f[0])
            return left
        def settle(secs):  # poll until no other member is left, up to <secs>; the members left
            end = time.time() + secs
            while True:
                left = others()
                if left == [] or time.time() >= end:
                    return left
                time.sleep(0.2)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        os.killpg(0, signal.SIGTERM)
        left = settle(5)
        end = time.time() + 10
        while left != [] and time.time() < end:
            for q in left or []:
                try:
                    os.kill(int(q), signal.SIGKILL)
                except (OSError, ValueError):
                    pass
            if left is None:  # no ps: fall back to the group as a whole, which would take this leader too
                break
            left = settle(min(1, max(0, end - time.time())))
        if left != []:
            with open(out + ".timeout.tmp", "w") as f:
                f.write("timeout after %ss, not stopped: %s\n" % (limit, " ".join(left) if left else "(ps unavailable)"))
            os.rename(out + ".timeout.tmp", out + ".timeout")
            while True:  # stay, so the run keeps an identity proc_stop can check and stop
                time.sleep(3600)
        with open(out, "ab") as o:
            o.write(("timeout after %ss\n" % limit).encode())
        r = 124
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
        [ ! -f "$out.timeout" ] || break
        [ $(( $(date +%s) - _ps )) -lt "$limit" ] || break
        sleep 2
    done
    if [ -f "$out.exit" ]; then echo "ended exit $(cat "$out.exit")"; return 0; fi
    _proc_id; id=$?
    [ $id != 1 ] || { _proc_late "$out"; return; }
    [ ! -f "$out.timeout" ] || { echo "running (timeout, not stopped)"; return 3; }
    if [ $(( $(date +%s) - _ps )) -ge "$limit" ]; then
        [ $id = 0 ] || { echo "ended timeout, not stopped: cannot check that $_pp is this run"; return 1; }
        _proc_kill; case $? in
        1) echo "ended timeout" ;;
        0) echo "ended timeout, still running $_pp" ;;
        *) echo "ended timeout, not stopped: cannot check the process group $_pp" ;;
        esac
        return 1
    fi
    [ $id = 0 ] && echo "running" || echo "running (identity unverified)"; return 3
}

proc_peek() {
    local out id; out=$(proc_canon "$1"); _proc_load "$out"
    if [ -f "$out.exit" ]; then echo "ended exit $(cat "$out.exit")"; return 0; fi
    _proc_id; id=$?
    [ $id != 1 ] || { _proc_late "$out"; return; }
    [ ! -f "$out.timeout" ] || { echo "running (timeout, not stopped)"; return 3; }
    [ $id = 0 ] && echo "running" || echo "running (identity unverified)"; return 3
}

proc_stop() {
    local out id; out=$(proc_canon "$1"); _proc_load "$out"
    [ -n "$_pp" ] || { echo "not stopped: no pid record at $out.pid"; return 1; }
    if ! kill -0 "$_pp" 2>/dev/null; then
        _proc_gstate; case $? in
        0) echo "not stopped: leader $_pp is gone but its process group still runs"; return 1 ;;
        2) echo "not stopped: leader $_pp is gone and its process group cannot be checked"; return 1 ;;
        esac
        _proc_stopped "$out"   # the group is provably empty: a timeout stop left unconfirmed is over now
        echo "ok not running"; return 0
    fi
    _proc_id; id=$?
    [ $id != 2 ] || { echo "not stopped: cannot check that $_pp is this run (identity unverified)"; return 1; }
    [ $id = 0 ] || { echo "not stopped: pid $_pp is not this run (identity check failed)"; return 1; }
    _proc_kill; case $? in
    1) _proc_stopped "$out"; echo "ok stopped"; return 0 ;;
    0) echo "not stopped: still running $_pp"; return 1 ;;
    esac
    echo "not stopped: cannot check the process group $_pp"; return 1
}
