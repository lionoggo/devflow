#!/usr/bin/env bash
# Cross-model review that outlives the call that starts it, for a host whose shell tool kills
# background processes when a call ends and whose calls should not block for minutes (Codex).
# Usage:
#   review.sh start <prompt-file> <out-file>  start the other model, read-only, in its own session;
#                                             prompt on stdin, stdout and stderr to <out-file>; prints the pid
#   review.sh wait <out-file> [seconds] [limit]
#                                             wait up to <seconds> (default 50) for it to end;
#                                             exit 0 "ended exit <code>" (also in <out-file>.exit),
#                                             3 "running" (or "running (identity unverified)": its pid is
#                                             alive and ps cannot check it), 1 "ended lost" (no exit code;
#                                             the pid is gone or provably another process) or "ended timeout" (over <limit>
#                                             seconds since start, default 1200; its process group is stopped,
#                                             or the line says it is still running or was not stopped)
# The wait only signals a process group whose leader is this review's wrapper (pid, start time and
# command equal to <out-file>.pid exactly); anything else, or anything ps cannot check, is reported,
# never killed. Times are wall-clock seconds.
# A start for an <out-file> whose review is still running, or whose pid is alive with its identity
# unverified, is refused (exit 1). Lifecycle: proc.sh.
# The other model: from Codex `claude -p --tools Read,Grep,Glob` (read and search only: plan mode would
# write a plan file under ~/.claude/plans); from Claude Code
# `codex exec -s read-only -`. DFLOW_REVIEW_CMD (a shell command) replaces it, for tests.
set -u
cmd=${1:-}
usage() { sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); . "$here/proc.sh"
case $cmd in
start)
    prompt=${2:-}; out=${3:-}; [ -f "$prompt" ] && [ -n "$out" ] || usage
    if [ -n "${DFLOW_REVIEW_CMD:-}" ]; then set -- sh -c "$DFLOW_REVIEW_CMD"
    elif [ "$(proc_host)" = codex ]; then set -- claude -p --tools Read,Grep,Glob
    else set -- codex exec -s read-only -
    fi
    proc_start "$out" "$@" < "$prompt" ;;
wait)
    out=${2:-}; [ -n "$out" ] || usage
    proc_wait "$out" "${3:-50}" "${4:-1200}" ;;
*) usage ;;
esac
