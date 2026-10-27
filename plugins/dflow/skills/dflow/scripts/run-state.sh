#!/usr/bin/env bash
# Mechanical state checks for a dflow unattended run (playbooks/unattended.md).
# Files, all under <repo>/.dflow/ and never committed:
#   <slug>.md     run manifest; its leading "key: value" block holds
#                 slug, branch, base, deadline (UTC, YYYY-mm-ddTHH:MM:SSZ), allow, protect
#   <slug>.lock/  the lease (atomic mkdir); lease file inside: session, pid, manifest_sha256, claimed_at, caffeinate_pid
#   <slug>.tsv    decision log (scripts/log.sh); "commit <sha>" in the evidence column marks a logged commit
#                 (a 多线 land writes "commit <new sha> from <source sha>": the new sha is the logged one)
#   <slug>.before/  no-commit runs: each path's content before the run first changed it (playbook)
#   <slug>.baseline.json  only with "commit: no" in the manifest: the dirty tree the user approved
#                 keeping, written once by `baseline` before claim (scripts/run-state-snap.py)
#
# Usage: run-state.sh baseline|claim|check|caffeinate|release|scope|state|changed <slug>
#        run-state.sh refresh <slug> <old manifest sha256>
# No-commit runs ("commit: no", only when the user approved keeping a dirty tree uncommitted):
#   check and scope compare the tree with the baseline instead of requiring it clean and reading
#   base..HEAD: HEAD stays at base, the index does not change, every path that differs from the
#   baseline (ignored files under allow and protect directories included) is inside allow and not
#   protected. What the comparison sees and refuses is in run-state-snap.py. Run baseline, state,
#   changed and scope while nothing else writes in the repo.
#   baseline    write <slug>.baseline.json; refused when it exists, after claim, or off base
#   state       the identity of what a check or review covered ("state <id>"): HEAD, or in a
#               no-commit run base, baseline, index and every changed path with its content
#   changed     no-commit runs: one JSON line [path, entry] per path that differs from the baseline
#   claim       take the lease for this session (a no-commit run: only after baseline); refused while another live agent process
#               (claude or codex) holds it, or while the holder pid is alive and ps cannot tell
#               what it is, and refused when this session's own pid is unknown or not running;
#               taking over a stale lease stops the previous
#               owner's caffeinate. The lock directory appears with its lease in one rename;
#               a stale lease is taken over inside the lease transaction, and the renamed lease must
#               still be the one judged stale (else it is put back and the claim refused)
# Lease transaction: refresh, caffeinate, release and a takeover change the lease only while holding
#   an exclusive flock on .dflow/.txn/<slug>.lock, on fd 9 of this script, re-reading the lease inside;
#   waited for up to DFLOW_LEASE_TXN_WAIT seconds (default 5), else refused, nothing changed. The kernel
#   drops the lock when its holder exits or is killed, so there is no owner record, no staleness and no
#   takeover of the transaction itself
# Session: the nearest claude or codex process above this shell is the host; its session id
#   is $CLAUDE_CODE_SESSION_ID or $CODEX_THREAD_ID and its pid is the owner pid.
#   DFLOW_SESSION_ID and DFLOW_AGENT_PID override both (tests).
#   check       per-round checks; exit 0 ok, 1 stop and report, 3 commits in base..HEAD that no
#               row names (one "UNLOGGED <sha>" line each, oldest first), 4 deadline passed
#   caffeinate  start `caffeinate -i` until the deadline and record its pid in this session's lease
#   refresh     after an approved manifest change (claim again keeps the old hash): only when this
#               session holds the lease and its manifest_sha256 is <old>, replace it atomically with
#               the current manifest's hash; prints "ok refreshed <old> -> <new>". Refused, nothing
#               changed: another session's lease, a wrong <old>, or a manifest that did not change
#   release     stop the recorded caffeinate (only if that pid is still caffeinate), drop the lease
#   scope       list files changed base..HEAD that are protected or outside allow; exit 1 if any
set -u
cmd=${1:-}; slug=${2:-}; arg3=${3:-}   # kept before host detection, which reuses the positional parameters
die() { echo "FAIL $*"; exit 1; }
usage='usage: run-state.sh baseline|claim|check|caffeinate|release|scope|state <slug> | refresh <slug> <old manifest sha256>'
[ -n "$cmd" ] && [ -n "$slug" ] || { echo "$usage" >&2; exit 2; }
printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$' || die "slug must match [a-z0-9][a-z0-9-]{0,62}: $slug"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
d="$root/.dflow"; man="$d/$slug.md"; lock="$d/$slug.lock"; lease="$lock/lease"; log="$d/$slug.tsv"
bl="$d/$slug.baseline.json"; sdir=$(cd "$(dirname "$0")" && pwd)
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
    read -r hname hpid <<< "$(host)"
    case $hname in
    codex) me=${CODEX_THREAD_ID:-}; mypid=$hpid ;;
    claude) me=${CLAUDE_CODE_SESSION_ID:-}; mypid=${CLAUDE_PID:-$hpid} ;;
    *) me=${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-}}; mypid=${CLAUDE_PID:-} ;;
    esac
fi

field() { # field <file> <key>: value from the leading key: value block
    awk -v k="$2" 'NF == 0 && seen { exit } /^[a-z0-9_]+: / { seen = 1; if (index($0, k ": ") == 1) { print substr($0, length(k) + 3); exit } }' "$1"
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null; }
is_agent() { # 0 a live claude or codex process, 1 not (gone, or another program), 2 alive but ps cannot
    # tell (DFLOW_OWNER_COMM names a stand-in for tests)
    local c
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
    c=$(ps -o comm= -p "$1" 2>/dev/null) && [ -n "$c" ] || return 2
    case $(basename "$c") in claude|codex|"${DFLOW_OWNER_COMM:-claude}") return 0 ;; esac
    return 1
}
rename() { python3 -I -c 'import os, sys
try: os.rename(sys.argv[1], sys.argv[2])
except OSError: sys.exit(1)' "$1" "$2"; }
install_lock() { # create $lock with this session's lease in one rename; fails when $lock exists
    local tmp="$lock.new.$$"; rm -rf "$tmp"; mkdir "$tmp" || return 1
    { echo "session: $me"; echo "pid: $mypid"; echo "manifest_sha256: $(sha "$man")"
      echo "claimed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "caffeinate_pid: "
      echo "baseline_sha256: $([ -f "$bl" ] && sha "$bl")"; } > "$tmp/lease"
    rename "$tmp" "$lock" && return 0
    rm -rf "$tmp"; return 1
}
age() { local m; m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || m=$(date +%s); echo $(( $(date +%s) - m )); }
txn() { # hold the lease transaction (an flock on $d/.txn/$slug.lock, fd 9) until this script exits:
    # every change to the lease (refresh, caffeinate, release, takeover) runs inside it. Waited for up to
    # DFLOW_LEASE_TXN_WAIT seconds (default 5), else refused
    local t="$d/.txn"
    printf '%s' "${DFLOW_LEASE_TXN_WAIT:-5}" | grep -Eq '^[0-9]+([.][0-9]+)?$' || die "DFLOW_LEASE_TXN_WAIT must be a number of seconds: ${DFLOW_LEASE_TXN_WAIT:-}"
    mkdir -p "$t" && exec 9>>"$t/$slug.lock" || die "cannot open the lease transaction $t/$slug.lock"
    python3 -I -c 'import fcntl, sys, time
end = time.time() + float(sys.argv[1])
while True:
    try:
        fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB); sys.exit(0)
    except OSError:
        if time.time() >= end: sys.exit(1)
        time.sleep(0.02)' "${DFLOW_LEASE_TXN_WAIT:-5}" 2>/dev/null ||
        { exec 9>&-; die "another change to the lease is in progress (it holds $t/$slug.lock); retry"; }
}
put_lease() { # put_lease <key> <value>: rewrite one lease line through a rename (call inside txn)
    sed "s/^$1: .*/$1: $2/" "$lease" > "$lease.tmp.$$" && mv -f "$lease.tmp.$$" "$lease" ||
        { rm -f "$lease.tmp.$$"; die "could not rewrite $lease"; }
}
need_manifest() {
    [ -f "$man" ] || die "missing manifest $man"
    for k in slug branch base deadline; do [ -n "$(field "$man" $k)" ] || die "manifest has no '$k:'"; done
    [ "$(field "$man" slug)" = "$slug" ] || die "manifest slug is not $slug"
}
nocommit() { [ "$(field "$man" commit)" = no ]; }
at_base() { # HEAD is the manifest base (a no-commit run never commits)
    local b h; b=$(git -C "$root" rev-parse --verify -q "$(field "$man" base)^{commit}") || die "manifest base not found"
    h=$(git -C "$root" rev-parse HEAD); [ "$h" = "$b" ] || die "HEAD $h is not base $b: a no-commit run never commits"
}
# snap <make|check|scope|state|changed>: the no-commit baseline, written and compared (see the header)
snap() { python3 -I "$sdir/run-state-snap.py" "$1" "$root" "$man" "$bl"; }

case $cmd in
claim)
    need_manifest; [ -n "$me" ] || die "no session id: run inside Claude Code or Codex (CLAUDE_CODE_SESSION_ID / CODEX_THREAD_ID)"
    printf '%s' "${mypid:-}" | grep -Eq '^[1-9][0-9]*$' && kill -0 "$mypid" 2>/dev/null ||
        die "cannot tell this session's agent pid (${mypid:-none}); a lease without a live owner pid would look stale at once"
    ! nocommit || [ -f "$bl" ] || die "no baseline $bl: a no-commit run writes it (run-state.sh baseline) before claim"
    mkdir -p "$d"
    if install_lock; then echo "ok claimed $slug"; exit 0; fi
    if [ ! -s "$lease" ]; then # a lock without a lease (an older claim died between mkdir and writing it)
        [ "$(age "$lock")" -gt 10 ] || die "another claim is in progress; retry"
    fi
    snap=$(cat "$lease" 2>/dev/null)
    owner=$(field "$lease" session 2>/dev/null); opid=$(field "$lease" pid 2>/dev/null)
    if [ "$owner" = "$me" ]; then echo "ok already held by this session"; exit 0; fi
    is_agent "$opid"; ia=$?
    [ $ia != 0 ] || die "held by session $owner (agent pid $opid is alive); close it first"
    [ $ia != 2 ] || die "held by session $owner: pid $opid is alive and ps cannot tell whether it is an agent; not taken over"
    # Stale lease. One taker at a time (the lease transaction); then rename, and check the renamed
    # lease is still the stale one.
    txn
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
    if nocommit; then
        [ -f "$bl" ] || die "no baseline $bl; a no-commit run writes it before claim"
        [ "$(field "$lease" baseline_sha256)" = "$(sha "$bl")" ] && echo "ok baseline unchanged" || die "baseline differs from the one this lease was claimed with"
        at_base; snap check || exit 1
        dl=$(epoch "$(field "$man" deadline)") || die "bad deadline"
        [ "$(date -u +%s)" -lt "$dl" ] && echo "ok before deadline" || { echo "DEADLINE passed"; exit 4; }
        exit 0
    fi
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
    txn; [ -f "$lease" ] || die "no lease"
    owner=$(field "$lease" session); [ -n "$me" ] && [ "$owner" = "$me" ] || die "lease held by session ${owner:-?}, not this one"
    secs=$(( $(epoch "$(field "$man" deadline)") - $(date -u +%s) )); [ "$secs" -gt 0 ] || die "deadline passed"
    command -v caffeinate >/dev/null || { echo "ok no caffeinate on this system"; exit 0; }
    # In a new session, so a host that kills the command's process group when the call ends
    # (Codex does) leaves it running; nohup alone is not enough there.
    pid=$(python3 -I -c 'import subprocess, sys
p = subprocess.Popen(["caffeinate", "-i", "-t", sys.argv[1]], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(p.pid)' "$secs" 2>/dev/null 9>&-) || { nohup caffeinate -i -t "$secs" >/dev/null 2>&1 9>&- & pid=$!; disown 2>/dev/null || true; }
    put_lease caffeinate_pid "$pid"
    echo "ok caffeinate pid $pid for ${secs}s" ;;
refresh)
    need_manifest; [ -f "$lease" ] || die "no lease; run claim"
    old=$arg3; [ -n "$old" ] || { echo "usage: run-state.sh refresh <slug> <old manifest sha256>" >&2; exit 2; }
    txn; [ -f "$lease" ] || die "no lease; run claim"   # owner and hash are read and written inside it
    owner=$(field "$lease" session)
    [ -n "$me" ] && [ "$owner" = "$me" ] || die "lease held by session ${owner:-?}, not this one; not refreshed"
    cur=$(field "$lease" manifest_sha256); new=$(sha "$man")
    [ "$cur" = "$old" ] || die "the lease's manifest_sha256 is $cur, not $old; not refreshed"
    [ "$new" != "$old" ] || die "manifest unchanged ($old); nothing to refresh"
    put_lease manifest_sha256 "$new"
    echo "ok refreshed $old -> $new" ;;
release)
    [ -f "$lease" ] || { echo "ok no lease"; exit 0; }
    txn; [ -f "$lease" ] || { echo "ok no lease"; exit 0; }
    owner=$(field "$lease" session)
    [ "$owner" = "$me" ] || die "lease held by session $owner, not this one"
    cp=$(field "$lease" caffeinate_pid)
    if [ -n "$cp" ] && ps -o comm= -p "$cp" 2>/dev/null | grep -q caffeinate; then kill "$cp" && echo "ok stopped caffeinate $cp"; fi
    rm -rf "$lock"; echo "ok released $slug" ;;
baseline)
    need_manifest; nocommit || die "baseline is only for a manifest with 'commit: no'"
    [ ! -e "$bl" ] || die "baseline $bl exists; it is written once, at 开始"
    [ ! -d "$lock" ] || die "write the baseline before claim"
    at_base; snap make || exit 1
    echo "ok baseline $(sha "$bl")" ;;
state)
    need_manifest
    if nocommit; then [ -f "$bl" ] || die "no baseline $bl"; snap state || exit 1; else echo "state $(git -C "$root" rev-parse HEAD)"; fi ;;
changed)
    need_manifest; nocommit || die "changed is for no-commit runs; use git diff <review head>..HEAD"
    [ -f "$bl" ] || die "no baseline $bl"; snap changed || exit 1 ;;
scope)
    need_manifest
    if nocommit; then [ -f "$bl" ] || die "no baseline $bl"; snap scope || exit 1; exit 0; fi
    set -f
    base=$(field "$man" base); allow=$(field "$man" allow); protect=$(field "$man" protect)
    bad=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        for p in $protect; do case $f in $p) echo "PROTECTED $f"; bad=1; continue 2 ;; esac; done
        inside=0; for p in $allow; do case $f in $p) inside=1 ;; esac; done
        [ -z "$allow" ] || [ $inside = 1 ] || { echo "OUTSIDE $f"; bad=1; }
    done <<< "$(git -C "$root" diff --name-only "$base"..HEAD)"
    [ $bad = 0 ] && echo "ok scope"; exit $bad ;;
*) echo "$usage" >&2; exit 2 ;;
esac
