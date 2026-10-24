#!/usr/bin/env bash
# Mechanical state checks for a dflow unattended run (playbooks/unattended.md).
# Files, all under <repo>/.dflow/ and never committed:
#   <slug>.md     run manifest; its leading "key: value" block holds
#                 slug, branch, base, deadline (UTC, YYYY-mm-ddTHH:MM:SSZ), allow, protect
#   <slug>.lock/  the lease (atomic mkdir); lease file inside: session, pid, manifest_sha256, claimed_at, caffeinate_pid
#   <slug>.tsv    decision log (scripts/log.sh); "commit <sha>" in the evidence column marks a logged commit
#
# Usage: run-state.sh claim|check|caffeinate|release|scope <slug>
#   claim       take the lease for this session; refused while another live agent process
#               (claude or codex) holds it; taking over a stale lease stops the previous
#               owner's caffeinate. The lock directory appears with its lease in one rename;
#               takers of a stale lease queue on <slug>.lock.takeover, and the renamed lease must
#               still be the one judged stale (else it is put back and the claim refused)
# Session: the nearest claude or codex process above this shell is the host; its session id
#   is $CLAUDE_CODE_SESSION_ID or $CODEX_THREAD_ID and its pid is the owner pid.
#   DFLOW_SESSION_ID and DFLOW_AGENT_PID override both (tests).
#   check       per-round checks; exit 0 ok, 1 stop and report, 3 commits in base..HEAD that no
#               row names (one "UNLOGGED <sha>" line each, oldest first), 4 deadline passed
#   caffeinate  start `caffeinate -i` until the deadline and record its pid in the lease
#   release     stop the recorded caffeinate (only if that pid is still caffeinate), drop the lease
#   scope       list files changed base..HEAD that are protected or outside allow; exit 1 if any
set -u
cmd=${1:-}; slug=${2:-}
die() { echo "FAIL $*"; exit 1; }
[ -n "$cmd" ] && [ -n "$slug" ] || { echo "usage: run-state.sh claim|check|caffeinate|release|scope <slug>" >&2; exit 2; }
printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$' || die "slug must match [a-z0-9][a-z0-9-]{0,62}: $slug"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
d="$root/.dflow"; man="$d/$slug.md"; lock="$d/$slug.lock"; lease="$lock/lease"; log="$d/$slug.tsv"
host() { # host: "<claude|codex> <pid>" of the nearest agent process above this shell, or "none"
    local p=$PPID c i=0
    while [ "${p:-0}" -gt 1 ] && [ $i -lt 40 ]; do
        c=$(basename "$(ps -o comm= -p "$p" 2>/dev/null)" 2>/dev/null)
        case $c in claude|codex) echo "$c $p"; return ;; esac
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i + 1))
    done
    echo none
}
if [ -n "${DFLOW_SESSION_ID:-}" ]; then me=$DFLOW_SESSION_ID; mypid=${DFLOW_AGENT_PID:-}
else
    set -- $(host)
    case $1 in
    codex) me=${CODEX_THREAD_ID:-}; mypid=$2 ;;
    claude) me=${CLAUDE_CODE_SESSION_ID:-}; mypid=${CLAUDE_PID:-$2} ;;
    *) me=${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-}}; mypid=${CLAUDE_PID:-} ;;
    esac
fi

field() { # field <file> <key>: value from the leading key: value block
    awk -v k="$2" 'NF == 0 && seen { exit } /^[a-z0-9_]+: / { seen = 1; if (index($0, k ": ") == 1) { print substr($0, length(k) + 3); exit } }' "$1"
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null; }
is_agent() { # a live claude or codex process (DFLOW_OWNER_COMM names a stand-in for tests)
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
    case $(basename "$(ps -o comm= -p "$1" 2>/dev/null)") in claude|codex|"${DFLOW_OWNER_COMM:-claude}") return 0 ;; esac
    return 1
}
rename() { python3 -I -c 'import os, sys
try: os.rename(sys.argv[1], sys.argv[2])
except OSError: sys.exit(1)' "$1" "$2"; }
install_lock() { # create $lock with this session's lease in one rename; fails when $lock exists
    local tmp="$lock.new.$$"; rm -rf "$tmp"; mkdir "$tmp" || return 1
    { echo "session: $me"; echo "pid: $mypid"; echo "manifest_sha256: $(sha "$man")"
      echo "claimed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "caffeinate_pid: "; } > "$tmp/lease"
    rename "$tmp" "$lock" && return 0
    rm -rf "$tmp"; return 1
}
need_manifest() {
    [ -f "$man" ] || die "missing manifest $man"
    for k in slug branch base deadline; do [ -n "$(field "$man" $k)" ] || die "manifest has no '$k:'"; done
    [ "$(field "$man" slug)" = "$slug" ] || die "manifest slug is not $slug"
}

case $cmd in
claim)
    need_manifest; [ -n "$me" ] || die "no session id: run inside Claude Code or Codex (CLAUDE_CODE_SESSION_ID / CODEX_THREAD_ID)"
    mkdir -p "$d"
    if install_lock; then echo "ok claimed $slug"; exit 0; fi
    age() { echo $(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1") )); }
    if [ ! -s "$lease" ]; then # a lock without a lease (an older claim died between mkdir and writing it)
        [ "$(age "$lock")" -gt 10 ] || die "another claim is in progress; retry"
    fi
    snap=$(cat "$lease" 2>/dev/null)
    owner=$(field "$lease" session 2>/dev/null); opid=$(field "$lease" pid 2>/dev/null)
    if [ "$owner" = "$me" ]; then echo "ok already held by this session"; exit 0; fi
    if is_agent "$opid"; then die "held by session $owner (agent pid $opid is alive); close it first"; fi
    # Stale lease. One taker at a time; then rename, and check the renamed lease is still the stale one.
    tk="$lock.takeover"
    if ! mkdir "$tk" 2>/dev/null; then
        [ "$(age "$tk")" -gt 10 ] && rename "$tk" "$tk.dead.$$" && rm -rf "$tk.dead.$$"
        mkdir "$tk" 2>/dev/null || die "another takeover of the stale lease is in progress; retry"
    fi
    trap 'rmdir "$tk" 2>/dev/null' EXIT
    [ "$(cat "$lease" 2>/dev/null)" = "$snap" ] || die "lost the race for a stale lease (it changed); retry"
    rename "$lock" "$lock.stale.$$" || die "lost the race for a stale lease; retry"
    if [ "$(cat "$lock.stale.$$/lease" 2>/dev/null)" != "$snap" ]; then
        rename "$lock.stale.$$" "$lock" || echo "FAIL could not put the lease back (left at $lock.stale.$$)"
        die "lost the race for a stale lease (another session took it); put back"
    fi
    ocp=$(field "$lock.stale.$$/lease" caffeinate_pid 2>/dev/null) # the dead owner's caffeinate would run to the deadline
    if [ -n "$ocp" ] && ps -o comm= -p "$ocp" 2>/dev/null | grep -q caffeinate; then kill "$ocp" && echo "ok stopped the previous owner's caffeinate $ocp"; fi
    rm -rf "$lock.stale.$$"
    install_lock || die "lost the race for a stale lease; retry"
    echo "ok took over stale lease from session ${owner:-?}"; exit 0 ;;
check)
    need_manifest; [ -f "$lease" ] || die "no lease; run claim"
    [ "$(field "$lease" session)" = "$me" ] && echo "ok lease" || { echo "FAIL lease held by session $(field "$lease" session), not this one"; exit 1; }
    [ "$(field "$lease" manifest_sha256)" = "$(sha "$man")" ] && echo "ok manifest unchanged" || die "manifest changed since claim"
    br=$(git -C "$root" rev-parse --abbrev-ref HEAD)
    [ "$br" = "$(field "$man" branch)" ] && echo "ok branch $br" || die "on branch $br, expected $(field "$man" branch)"
    dirty=$(git -C "$root" status --porcelain --untracked-files=all | grep -v ' \.dflow/' || true)
    [ -z "$dirty" ] && echo "ok clean" || { echo "FAIL uncommitted changes of unknown origin:"; echo "$dirty"; exit 1; }
    logged=$(awk -F'\t' '{ s = $5; while (match(s, /commit [0-9a-f]{7,40}/)) { print substr(s, RSTART + 7, RLENGTH - 7); s = substr(s, RSTART + RLENGTH) } }' "$log" 2>/dev/null)
    mbase=$(git -C "$root" rev-parse --verify -q "$(field "$man" base)^{commit}") || die "manifest base not found"
    last=$(printf '%s\n' "$logged" | tail -1)
    [ -n "$last" ] || last=$mbase
    last=$(git -C "$root" rev-parse --verify -q "$last^{commit}") || die "logged commit not found"
    head=$(git -C "$root" rev-parse HEAD)
    dl=$(epoch "$(field "$man" deadline)") || die "bad deadline"
    git -C "$root" merge-base --is-ancestor "$last" HEAD || die "HEAD $head does not contain the last logged commit $last"
    unl=$(git -C "$root" rev-list --reverse "$mbase..HEAD" | while read -r c; do
        printf '%s\n' "$logged" | awk -v c="$c" 'NF && index(c, $0) == 1 { f = 1 } END { exit !f }' || echo "$c"; done)
    if [ -n "$unl" ]; then printf 'UNLOGGED %s\n' $unl; exit 3; fi
    echo "ok head $head"
    [ "$(date -u +%s)" -lt "$dl" ] && echo "ok before deadline" || { echo "DEADLINE passed"; exit 4; } ;;
caffeinate)
    need_manifest; [ -f "$lease" ] || die "no lease"
    secs=$(( $(epoch "$(field "$man" deadline)") - $(date -u +%s) )); [ "$secs" -gt 0 ] || die "deadline passed"
    command -v caffeinate >/dev/null || { echo "ok no caffeinate on this system"; exit 0; }
    # In a new session, so a host that kills the command's process group when the call ends
    # (Codex does) leaves it running; nohup alone is not enough there.
    pid=$(python3 -I -c 'import subprocess, sys
p = subprocess.Popen(["caffeinate", "-i", "-t", sys.argv[1]], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(p.pid)' "$secs" 2>/dev/null) || { nohup caffeinate -i -t "$secs" >/dev/null 2>&1 & pid=$!; disown 2>/dev/null || true; }
    sed -i.bak "s/^caffeinate_pid: .*/caffeinate_pid: $pid/" "$lease" && rm -f "$lease.bak"
    echo "ok caffeinate pid $pid for ${secs}s" ;;
release)
    [ -f "$lease" ] || { echo "ok no lease"; exit 0; }
    owner=$(field "$lease" session)
    [ "$owner" = "$me" ] || die "lease held by session $owner, not this one"
    cp=$(field "$lease" caffeinate_pid)
    if [ -n "$cp" ] && ps -o comm= -p "$cp" 2>/dev/null | grep -q caffeinate; then kill "$cp" && echo "ok stopped caffeinate $cp"; fi
    rm -rf "$lock"; echo "ok released $slug" ;;
scope)
    need_manifest; set -f
    base=$(field "$man" base); allow=$(field "$man" allow); protect=$(field "$man" protect)
    bad=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        for p in $protect; do case $f in $p) echo "PROTECTED $f"; bad=1; continue 2 ;; esac; done
        inside=0; for p in $allow; do case $f in $p) inside=1 ;; esac; done
        [ -z "$allow" ] || [ $inside = 1 ] || { echo "OUTSIDE $f"; bad=1; }
    done <<< "$(git -C "$root" diff --name-only "$base"..HEAD)"
    [ $bad = 0 ] && echo "ok scope"; exit $bad ;;
*) echo "usage: run-state.sh claim|check|caffeinate|release|scope <slug>" >&2; exit 2 ;;
esac
