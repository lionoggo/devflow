#!/usr/bin/env bash
# Mechanical state checks for a dflow unattended run (playbooks/unattended.md).
# Files, all under <repo>/.dflow/ and never committed:
#   <slug>.md     run manifest; its leading "key: value" block holds
#                 slug, branch, base, deadline (UTC, YYYY-mm-ddTHH:MM:SSZ), allow, protect
#   <slug>.lock/  the lease (atomic mkdir); lease file inside: session, pid, manifest_sha256, claimed_at, caffeinate_pid
#   <slug>.tsv    decision log (scripts/log.sh); "commit <sha>" in the evidence column marks a logged commit
#
# Usage: run-state.sh claim|check|caffeinate|release|scope <slug>
#   claim       take the lease for this session ($CLAUDE_CODE_SESSION_ID, $CLAUDE_PID);
#               refused while another live claude process holds it
#   check       per-round checks; exit 0 ok, 1 stop and report, 3 exactly one unlogged commit
#               on top of the last logged one (prints its sha), 4 deadline passed
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
me=${CLAUDE_CODE_SESSION_ID:-}; mypid=${CLAUDE_PID:-}

field() { # field <file> <key>: value from the leading key: value block
    awk -v k="$2" 'NF == 0 && seen { exit } /^[a-z0-9_]+: / { seen = 1; if (index($0, k ": ") == 1) { print substr($0, length(k) + 3); exit } }' "$1"
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null; }
owner_comm=${DFLOW_OWNER_COMM:-claude}   # process name of a live owner; tests override it
is_claude() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && [ "$(basename "$(ps -o comm= -p "$1" 2>/dev/null)")" = "$owner_comm" ]; }
write_lease() {
    { echo "session: $me"; echo "pid: $mypid"; echo "manifest_sha256: $(sha "$man")"
      echo "claimed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "caffeinate_pid: ${1:-}"; } > "$lease.tmp" && mv "$lease.tmp" "$lease"
}
need_manifest() {
    [ -f "$man" ] || die "missing manifest $man"
    for k in slug branch base deadline; do [ -n "$(field "$man" $k)" ] || die "manifest has no '$k:'"; done
    [ "$(field "$man" slug)" = "$slug" ] || die "manifest slug is not $slug"
}

case $cmd in
claim)
    need_manifest; [ -n "$me" ] || die "CLAUDE_CODE_SESSION_ID is not set"
    mkdir -p "$d"
    if mkdir "$lock" 2>/dev/null; then write_lease; echo "ok claimed $slug"; exit 0; fi
    if [ ! -s "$lease" ]; then # another claim is between mkdir and writing the lease
        age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock") ))
        [ "$age" -gt 10 ] || die "another claim is in progress; retry"
    fi
    owner=$(field "$lease" session 2>/dev/null); opid=$(field "$lease" pid 2>/dev/null)
    if [ "$owner" = "$me" ]; then echo "ok already held by this session"; exit 0; fi
    if is_claude "$opid"; then die "held by session $owner (claude pid $opid is alive); close it first"; fi
    # Stale lease: rename is atomic, so only one taker wins.
    mv "$lock" "$lock.stale.$$" 2>/dev/null || die "lost the race for a stale lease; retry"
    rm -rf "$lock.stale.$$"
    mkdir "$lock" 2>/dev/null || die "lost the race for a stale lease; retry"
    write_lease; echo "ok took over stale lease from session ${owner:-?}"; exit 0 ;;
check)
    need_manifest; [ -f "$lease" ] || die "no lease; run claim"
    [ "$(field "$lease" session)" = "$me" ] && echo "ok lease" || { echo "FAIL lease held by session $(field "$lease" session), not this one"; exit 1; }
    [ "$(field "$lease" manifest_sha256)" = "$(sha "$man")" ] && echo "ok manifest unchanged" || die "manifest changed since claim"
    br=$(git -C "$root" rev-parse --abbrev-ref HEAD)
    [ "$br" = "$(field "$man" branch)" ] && echo "ok branch $br" || die "on branch $br, expected $(field "$man" branch)"
    dirty=$(git -C "$root" status --porcelain --untracked-files=all | grep -v ' \.dflow/' || true)
    [ -z "$dirty" ] && echo "ok clean" || { echo "FAIL uncommitted changes of unknown origin:"; echo "$dirty"; exit 1; }
    last=$(awk -F'\t' '{ if (match($5, /commit [0-9a-f]{7,40}/)) s = substr($5, RSTART + 7, RLENGTH - 7) } END { print s }' "$log" 2>/dev/null)
    [ -n "$last" ] || last=$(field "$man" base)
    last=$(git -C "$root" rev-parse --verify -q "$last^{commit}") || die "logged commit not found"
    head=$(git -C "$root" rev-parse HEAD)
    dl=$(epoch "$(field "$man" deadline)") || die "bad deadline"
    if [ "$head" != "$last" ]; then
        if [ "$(git -C "$root" rev-parse -q --verify "HEAD^" 2>/dev/null)" = "$last" ]; then
            echo "UNLOGGED $head"; exit 3
        fi
        die "HEAD $head is not the last logged commit $last"
    fi
    echo "ok head $head"
    [ "$(date -u +%s)" -lt "$dl" ] && echo "ok before deadline" || { echo "DEADLINE passed"; exit 4; } ;;
caffeinate)
    need_manifest; [ -f "$lease" ] || die "no lease"
    secs=$(( $(epoch "$(field "$man" deadline)") - $(date -u +%s) )); [ "$secs" -gt 0 ] || die "deadline passed"
    command -v caffeinate >/dev/null || { echo "ok no caffeinate on this system"; exit 0; }
    nohup caffeinate -i -t "$secs" >/dev/null 2>&1 &
    pid=$!; disown 2>/dev/null || true
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
