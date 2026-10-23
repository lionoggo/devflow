#!/usr/bin/env bash
# Cross-model review that outlives the call that starts it, for a host whose shell tool kills
# background processes when a call ends and whose calls should not block for minutes (Codex).
# Usage:
#   review.sh start <prompt-file> <out-file>  start the other model, read-only, in its own session;
#                                             prompt on stdin, stdout and stderr to <out-file>; prints the pid
#   review.sh wait <out-file> [seconds] [limit]
#                                             wait up to <seconds> (default 50) for it to end;
#                                             exit 0 "ended exit <code>" (also in <out-file>.exit),
#                                             3 "running", 1 "ended lost" (no exit code and no live process
#                                             of this review on record) or "ended timeout" (over <limit>
#                                             seconds since start, default 1200; its process group is stopped,
#                                             or "ended timeout, still running <pgid>" when it would not stop)
# The wait only signals a process group whose leader is this review's wrapper (its command names
# <out-file>); anything else is reported, never killed. Times are wall-clock seconds.
# The other model: from Codex `claude -p --tools Read,Grep,Glob` (read and search only: plan mode would
# write a plan file under ~/.claude/plans); from Claude Code
# `codex exec -s read-only -`. DFLOW_REVIEW_CMD (a shell command) replaces it, for tests.
set -u
cmd=${1:-}
usage() { sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
host() { # nearest claude or codex process above this shell
    local p=$PPID c i=0
    while [ "${p:-0}" -gt 1 ] && [ $i -lt 40 ]; do
        c=$(basename "$(ps -o comm= -p "$p" 2>/dev/null)" 2>/dev/null)
        case $c in claude|codex) echo "$c"; return ;; esac
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i + 1))
    done
    echo none
}
case $cmd in
start)
    prompt=${2:-}; out=${3:-}; [ -f "$prompt" ] && [ -n "$out" ] || usage
    case $out in /*) ;; *) out="$PWD/$out" ;; esac
    if [ -n "${DFLOW_REVIEW_CMD:-}" ]; then set -- sh -c "$DFLOW_REVIEW_CMD"
    elif [ "$(host)" = codex ]; then set -- claude -p --tools Read,Grep,Glob
    else set -- codex exec -s read-only -
    fi
    rm -f "$out.exit" "$out.pid"
    python3 -I - "$prompt" "$out" "$@" <<'PY'
import os, subprocess, sys, time
prompt, out, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
pid = os.fork()
if pid:
    with open(out + ".pid", "w") as f:
        f.write("%d %d\n" % (pid, int(time.time())))  # for wait: pid and start time
    print(pid)
    sys.exit(0)
os.setsid()  # its own session: the host's end-of-call cleanup does not reach it
null = os.open(os.devnull, os.O_RDWR)
for fd in (0, 1, 2):
    os.dup2(null, fd)  # release the caller's pipes so the call returns now
with open(prompt, "rb") as i, open(out, "wb") as o:
    try:
        r = subprocess.call(cmd, stdin=i, stdout=o, stderr=subprocess.STDOUT)
    except OSError as e:
        o.write(("cannot start %s: %s\n" % (cmd[0], e)).encode())
        r = 127
with open(out + ".exit", "w") as f:
    f.write("%d\n" % r)
PY
    ;;
wait)
    out=${2:-}; secs=${3:-50}; limit=${4:-1200}; [ -n "$out" ] || usage
    case $out in /*) ;; *) out="$PWD/$out" ;; esac
    pid=""; started=""
    [ -f "$out.pid" ] && read -r pid started < "$out.pid" 2>/dev/null
    case "$pid:$started" in *[!0-9:]*|:*|*:) pid=""; started="" ;; esac  # missing or old format: no record
    mine() { # the recorded pid still leads this review's process group
        [ -n "$pid" ] && [ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$pid" ] &&
            ps -ww -o command= -p "$pid" 2>/dev/null | grep -qF -- "$out"
    }
    end=$(( $(date +%s) + secs ))
    while [ ! -f "$out.exit" ] && [ "$(date +%s)" -lt "$end" ]; do
        mine || break
        [ $(( $(date +%s) - started )) -lt "$limit" ] || break
        sleep 2
    done
    if [ -f "$out.exit" ]; then echo "ended exit $(cat "$out.exit")"; exit 0; fi
    mine || { echo "ended lost"; exit 1; }
    if [ $(( $(date +%s) - started )) -ge "$limit" ]; then
        kill -TERM -- -"$pid" 2>/dev/null
        for _ in 1 2 3 4 5; do pgrep -g "$pid" >/dev/null || break; sleep 1; done
        pgrep -g "$pid" >/dev/null && { kill -KILL -- -"$pid" 2>/dev/null; sleep 1; }
        if pgrep -g "$pid" >/dev/null; then echo "ended timeout, still running $pid"; else echo "ended timeout"; fi
        exit 1
    fi
    echo "running"; exit 3 ;;
*) usage ;;
esac
