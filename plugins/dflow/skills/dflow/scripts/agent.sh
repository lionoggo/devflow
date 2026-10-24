#!/usr/bin/env bash
# Headless worker for dflow 多线 (playbooks/lines.md): the other model, with full permissions, in the
# line's worktree, in its own session so it outlives the call that starts it (lifecycle: proc.sh).
# Usage:
#   agent.sh start <slug> <id> <attempt> <brief-file> <worktree> [claude|codex]
#                 brief on stdin; its first line must be "dflow 线 <slug>/<id>/<attempt>" for these
#                 arguments. The attempt is claimed first with mkdir .dflow/<slug>/run/<id>-<attempt>.claim:
#                 an attempt claimed before (or started at the same moment by another call) is refused
#                 and nothing of it is overwritten; start <attempt>+1. Output to
#                 <repo>/.dflow/<slug>/run/<id>-<attempt>.out, one file per attempt; prints the pid.
#                 Claude: `claude -p --dangerously-skip-permissions`; Codex:
#                 `codex exec --dangerously-bypass-approvals-and-sandbox -C <worktree> -`. Without a
#                 model, the other host's: Claude from Codex, else Codex. The command also gets
#                 DFLOW_LINE=<slug>/<id>/<attempt> and DFLOW_RECEIPT=<absolute receipt path>.
#                 DFLOW_AGENT_CMD (a shell command) replaces it, for tests
#   agent.sh wait <slug> <id> <attempt> [seconds] [limit]
#                 proc_wait (default 50 seconds; limit default 3600 since start, then the worker's process
#                 group is stopped), then the receipt .dflow/<slug>/reports/<id>-<attempt>.md:
#                 exit 0 "delivered <done|partial|blocked> <sha|path>" (ended, receipt valid for this id
#                 and attempt), 1 "exited without receipt" (ended; commits on the branch do not count),
#                 3 "running" or "running (identity unverified)" (the pid is alive and cannot be checked:
#                 not ended, not lost, never signalled), 1 "ended lost" or "ended timeout..." as proc_wait
#                 prints them
#   agent.sh peek <slug> <id> <attempt>
#                 the same answers as wait, from one look: never waits, never signals, no limit
#   agent.sh stop <slug> <id> <attempt>
#                 proc_stop: "ok stopped" / "ok not running", or exit 1 "not stopped: <reason>" (the
#                 identity check failed or could not be made, or the group is still there; nothing
#                 else is signalled)
# Exit 0 ok, 1 refused or not done, 2 usage, 3 running.
set -u
cmd=${1:-}; slug=${2:-}; uid=${3:-}; att=${4:-}
die() { echo "FAIL $*"; exit 1; }
usage() { sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); . "$here/proc.sh"
[ -n "$cmd" ] && [ -n "$slug" ] && [ -n "$uid" ] && [ -n "$att" ] || usage
printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$' || die "bad slug: $slug"
printf '%s' "$uid" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$' || die "bad id: $uid"
printf '%s' "$att" | grep -Eq '^[1-9][0-9]{0,5}$' || die "bad attempt: $att"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
out="$root/.dflow/$slug/run/$uid-$att.out"

case $cmd in
start)
    brief=${5:-}; wt=${6:-}; model=${7:-}
    [ -f "$brief" ] && [ -n "$wt" ] || usage
    [ -d "$wt" ] || die "no worktree $wt"
    wt=$(cd "$wt" && pwd -P); brief=$(proc_canon "$brief")
    [ -n "$model" ] || { [ "$(proc_host)" = codex ] && model=claude || model=codex; }
    if [ -n "${DFLOW_AGENT_CMD:-}" ]; then set -- sh -c "$DFLOW_AGENT_CMD"
    else case $model in
        claude) set -- claude -p --dangerously-skip-permissions ;;
        codex) set -- codex exec --dangerously-bypass-approvals-and-sandbox -C "$wt" - ;;
        *) usage ;;
    esac; fi
    first=$(head -1 "$brief" | tr -d '\r')
    [ "$first" = "dflow 线 $slug/$uid/$att" ] || die "brief $brief starts with \"$first\", not \"dflow 线 $slug/$uid/$att\""
    mkdir -p "$root/.dflow/$slug/run" || die "cannot create $root/.dflow/$slug/run"
    mkdir "${out%.out}.claim" 2>/dev/null || die "attempt $slug/$uid/$att was claimed before (${out%.out}.claim; $(proc_peek "$out")); start attempt $((att + 1)) instead"
    if [ -e "$out" ] || [ -e "$out.pid" ]; then
        die "attempt $slug/$uid/$att was started before ($(proc_peek "$out"); $out); start attempt $((att + 1)) instead"
    fi
    export DFLOW_LINE="$slug/$uid/$att" DFLOW_RECEIPT="$root/.dflow/$slug/reports/$uid-$att.md"
    cd "$wt" || exit 1
    proc_start "$out" "$@" < "$brief" ;;
wait|peek)
    if [ "$cmd" = wait ]; then st=$(proc_wait "$out" "${5:-50}" "${6:-3600}"); rc=$?
    else st=$(proc_peek "$out"); rc=$?; fi
    case $rc:$st in
    "0:ended exit"*)
        if r=$("$here/lines.sh" receipt "$slug" "$uid" "$att" 2>&1); then echo "delivered $r"; exit 0; fi
        echo "exited without receipt"; exit 1 ;;
    esac
    echo "$st"; exit $rc ;;
stop) proc_stop "$out" ;;
*) usage ;;
esac
