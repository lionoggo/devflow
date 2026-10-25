#!/usr/bin/env bash
# Tests for run-state.sh against a throwaway repo.
set -u
here=$(cd "$(dirname "$0")" && pwd); rs="$here/run-state.sh"; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
expect() { # expect <exit> <desc> <cmd...>
    local want=$1 desc=$2; shift 2; out=$("$@" 2>&1); got=$?
    [ "$got" = "$want" ] && ok || bad "$desc: exit $got, want $want: $out"
}
t=$(mktemp -d "${TMPDIR:-/tmp}/run-state-test.XXXXXX")
pids=(); trap 'kill "${pids[@]}" 2>/dev/null; rm -rf "$t"' EXIT
r="$t/repo"; git init -q "$r"; cd "$r"; git config user.email t@t; git config user.name t
mkdir -p src tests; echo a > src/a.py; echo t > tests/t.py; git add -A; git commit -qm base
base=$(git rev-parse HEAD); git checkout -qb dflow/demo
mkdir -p .dflow; echo '.dflow/' >> .git/info/exclude
future=$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
cat > .dflow/demo.md <<M
slug: demo
branch: dflow/demo
base: $base
deadline: $future
allow: src/*
protect: tests/*

# 目标
demo
M
export DFLOW_SESSION_ID=s1 DFLOW_AGENT_PID=$$

expect 1 "bad slug" "$rs" check "../x"
expect 1 "check before claim" "$rs" check demo
expect 0 "claim" "$rs" claim demo
expect 0 "re-claim same session" "$rs" claim demo
expect 0 "check fresh" "$rs" check demo

# a live process named claude holds the lease -> refused
export DFLOW_OWNER_COMM=sleep   # stand-in for a live claude process
sleep 60 & pids+=($!); cpid=$!
DFLOW_SESSION_ID=s2 DFLOW_AGENT_PID=$cpid "$rs" release demo >/dev/null 2>&1
sed -i '' "s/^session: .*/session: s2/; s/^pid: .*/pid: $cpid/" .dflow/demo.lock/lease
expect 1 "claim refused while claude alive" "$rs" claim demo
# pid reused by a non-claude process -> takeover allowed
tail -f /dev/null & pids+=($!); spid=$!
sed -i '' "s/^pid: .*/pid: $spid/" .dflow/demo.lock/lease
if command -v caffeinate >/dev/null; then
    caffeinate -i -t 120 & oldc=$!; sed -i '' "s/^caffeinate_pid: .*/caffeinate_pid: $oldc/" .dflow/demo.lock/lease
fi
expect 0 "takeover when pid is not claude" "$rs" claim demo
grep -q '^session: s1' .dflow/demo.lock/lease && ok || bad "lease not rewritten"
if [ -n "${oldc:-}" ]; then sleep 0.3; kill -0 "$oldc" 2>/dev/null && { bad "previous owner's caffeinate left running"; kill "$oldc"; } || ok; fi

# concurrent fresh claims: exactly one wins
DFLOW_SESSION_ID=s1 "$rs" release demo >/dev/null
rp=(); for i in 1 2 3 4 5 6; do (DFLOW_SESSION_ID=c$i DFLOW_AGENT_PID=$cpid "$rs" claim demo >/dev/null 2>&1 && echo won >> "$t/race") & rp+=($!); done; wait "${rp[@]}"; touch "$t/race"
kill "${pids[@]}" 2>/dev/null; pids=()
[ "$(grep -c won "$t/race")" = 1 ] && ok || bad "concurrent claims: $(grep -c won "$t/race") won"
# concurrent takeovers of one stale lease: exactly one wins, the lease names it, nothing is left behind
sh -c 'exit 0' & dead=$!; wait "$dead"
sleep 60 & pids+=($!); live=$!
sed -i '' "s/^session: .*/session: gone/; s/^pid: .*/pid: $dead/" .dflow/demo.lock/lease
: > "$t/take"; rp=()
for i in 1 2 3 4 5 6 7 8; do (DFLOW_SESSION_ID=t$i DFLOW_AGENT_PID=$live "$rs" claim demo >/dev/null 2>&1 && echo "t$i" >> "$t/take") & rp+=($!); done; wait "${rp[@]}"
[ "$(wc -l < "$t/take" | tr -d ' ')" = 1 ] && grep -qx "session: $(cat "$t/take")" .dflow/demo.lock/lease && ok || bad "concurrent takeovers: winners $(tr '\n' ' ' < "$t/take"), lease $(grep session .dflow/demo.lock/lease)"
[ -z "$(ls -d .dflow/demo.lock.* 2>/dev/null)" ] && ok || bad "takeover left $(ls -d .dflow/demo.lock.*)"
kill "$live" 2>/dev/null
# the holder pid is alive but ps cannot tell what it is (a sandbox refusing ps): not taken over
mkdir -p "$t/nops"; printf '#!/bin/sh\necho "ps: operation not permitted" >&2; exit 1\n' > "$t/nops/ps"; chmod +x "$t/nops/ps"
sleep 60 & pids+=($!); live=$!
sed -i '' "s/^session: .*/session: gone/; s/^pid: .*/pid: $live/" .dflow/demo.lock/lease; cp .dflow/demo.lock/lease "$t/lease"
out=$(PATH="$t/nops:$PATH" DFLOW_OWNER_COMM=none DFLOW_SESSION_ID=t9 "$rs" claim demo 2>&1); rc=$?
[ $rc = 1 ] && cmp -s .dflow/demo.lock/lease "$t/lease" && ok || bad "no ps: live holder taken over: $rc $out"
kill "$live" 2>/dev/null
# a claim whose own pid is unknown or not running is refused: its lease would look stale at once
rm -rf .dflow/demo.lock
DFLOW_AGENT_PID= expect 1 "claim without an owner pid" "$rs" claim demo
[ ! -d .dflow/demo.lock ] && ok || bad "lease written without an owner pid"
DFLOW_AGENT_PID=$dead expect 1 "claim with a dead owner pid" "$rs" claim demo
rm -rf .dflow/demo.lock; expect 0 "claim again" "$rs" claim demo

# manifest change detected
cp .dflow/demo.md "$t/m"; echo extra >> .dflow/demo.md
expect 1 "manifest changed" "$rs" check demo
cp "$t/m" .dflow/demo.md
# S3: an approved manifest change. Claim again keeps the lease's old hash, so check still fails (as
# before); refresh <old hash> moves it to the new one. A wrong old hash, another session, or a manifest
# that did not change is refused and leaves the lease as it was
oh=$(sed -n 's/^manifest_sha256: //p' .dflow/demo.lock/lease)
cp .dflow/demo.md "$t/m3"; echo "approved: one more file" >> .dflow/demo.md
nh=$(shasum -a 256 .dflow/demo.md | cut -d' ' -f1)
expect 0 "claim after the change" "$rs" claim demo
expect 1 "claim does not refresh the manifest hash" "$rs" check demo
cp .dflow/demo.lock/lease "$t/lease3"
out=$("$rs" refresh demo 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef 2>&1); rc=$?
[ $rc = 1 ] && cmp -s .dflow/demo.lock/lease "$t/lease3" && ok || bad "refresh with a wrong old hash: $rc $out"
out=$(DFLOW_SESSION_ID=s9 "$rs" refresh demo "$oh" 2>&1); rc=$?
[ $rc = 1 ] && cmp -s .dflow/demo.lock/lease "$t/lease3" && ok || bad "refresh by another session: $rc $out"
out=$("$rs" refresh demo "$oh" 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = "ok refreshed $oh -> $nh" ] && grep -qx "manifest_sha256: $nh" .dflow/demo.lock/lease && ok || bad "refresh: $rc $out"
grep -qx "session: s1" .dflow/demo.lock/lease && [ -z "$(ls -d .dflow/demo.lock/lease.* 2>/dev/null)" ] && ok || bad "refresh changed more than the hash: $(cat .dflow/demo.lock/lease)"
expect 0 "check after refresh" "$rs" check demo
cp .dflow/demo.lock/lease "$t/lease3"
out=$("$rs" refresh demo "$nh" 2>&1); rc=$?
[ $rc = 1 ] && cmp -s .dflow/demo.lock/lease "$t/lease3" && ok || bad "refresh with an unchanged manifest: $rc $out"
cp "$t/m3" .dflow/demo.md; expect 0 "refresh back" "$rs" refresh demo "$nh"
# T1: the session comes from the host (no DFLOW_SESSION_ID): refresh keeps its <old> argument
cp .dflow/demo.lock/lease "$t/lease5"; oh=$(sed -n 's/^manifest_sha256: //p' .dflow/demo.lock/lease)
sed -i '' "s/^session: .*/session: h1/" .dflow/demo.lock/lease
cp .dflow/demo.md "$t/m5"; echo "approved: host" >> .dflow/demo.md; nh=$(shasum -a 256 .dflow/demo.md | cut -d' ' -f1)
out=$(env -u DFLOW_SESSION_ID -u DFLOW_AGENT_PID CLAUDE_CODE_SESSION_ID=h1 CODEX_THREAD_ID=h1 CLAUDE_PID=$$ "$rs" refresh demo "$oh" 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = "ok refreshed $oh -> $nh" ] && grep -qx "manifest_sha256: $nh" .dflow/demo.lock/lease && ok || bad "refresh with the host's session: $rc $out"
cp "$t/m5" .dflow/demo.md; cp "$t/lease5" .dflow/demo.lock/lease
# T5: two refreshes from the same old hash at once: exactly one wins (a slow shasum holds each one
# between reading the lease and writing it)
mkdir -p "$t/slowsha"; printf '#!/bin/sh\nsleep 1\nexec %s "$@"\n' "$(command -v shasum)" > "$t/slowsha/shasum"; chmod +x "$t/slowsha/shasum"
oh=$(sed -n 's/^manifest_sha256: //p' .dflow/demo.lock/lease)
cp .dflow/demo.md "$t/m6"; echo "approved: race" >> .dflow/demo.md; nh=$(shasum -a 256 .dflow/demo.md | cut -d' ' -f1)
: > "$t/rr"; rp=()
for i in 1 2; do (PATH="$t/slowsha:$PATH" "$rs" refresh demo "$oh" > "$t/rr$i" 2>&1 && echo won >> "$t/rr") & rp+=($!); done; wait "${rp[@]}"
[ "$(grep -c won "$t/rr")" = 1 ] && grep -qx "manifest_sha256: $nh" .dflow/demo.lock/lease && ok || bad "concurrent refreshes: $(grep -c won "$t/rr") won: $(cat "$t/rr1" "$t/rr2")"
[ -z "$(ls -d .dflow/demo.lock.* 2>/dev/null)" ] && ok || bad "refresh left $(ls -d .dflow/demo.lock.*)"
cp "$t/m6" .dflow/demo.md; expect 0 "refresh back after the race" "$rs" refresh demo "$nh"
# T5: a live lease transaction makes refresh wait, then refuse; one left over 10s ago is taken over
oh=$(sed -n 's/^manifest_sha256: //p' .dflow/demo.lock/lease); cp .dflow/demo.md "$t/m7"; echo "approved: txn" >> .dflow/demo.md
mkdir .dflow/demo.lock.txn; cp .dflow/demo.lock/lease "$t/lease7"
out=$(DFLOW_LEASE_TXN_WAIT=1 "$rs" refresh demo "$oh" 2>&1); rc=$?
[ $rc = 1 ] && cmp -s .dflow/demo.lock/lease "$t/lease7" && [ -d .dflow/demo.lock.txn ] && ok || bad "refresh during another lease transaction: $rc $out"
touch -t 200001010000 .dflow/demo.lock.txn
out=$("$rs" refresh demo "$oh" 2>&1); rc=$?
[ $rc = 0 ] && [ ! -e .dflow/demo.lock.txn ] && ok || bad "refresh over a lease transaction left 10s ago: $rc $out"
nh=$(shasum -a 256 .dflow/demo.md | cut -d' ' -f1); cp "$t/m7" .dflow/demo.md; expect 0 "refresh back after the txn test" "$rs" refresh demo "$nh"

# dirty tree of unknown origin
echo x > src/new.py; expect 1 "dirty tree" "$rs" check demo; rm src/new.py

# unlogged commits -> exit 3 listing each; logged (any position in the row) -> ok; HEAD behind -> 1
echo b >> src/a.py; git commit -qam one; c1=$(git rev-parse HEAD)
expect 3 "one unlogged commit" "$rs" check demo
"$here/log.sh" .dflow/demo.tsv round "a" "b" "commit $c1" ok
expect 0 "logged commit" "$rs" check demo
echo c >> src/a.py; git commit -qam two; c2=$(git rev-parse HEAD); echo d >> src/a.py; git commit -qam three; c3=$(git rev-parse HEAD)
out=$("$rs" check demo); [ $? = 3 ] && ok || bad "two unlogged exit: $out"
[ "$(echo "$out" | grep '^UNLOGGED' | tr '\n' ' ')" = "UNLOGGED $c2 UNLOGGED $c3 " ] && ok || bad "two unlogged listing: $out"
"$here/log.sh" .dflow/demo.tsv round "a" "b" "commit ${c2:0:7}; commit ${c3:0:7}" ok
expect 0 "two commits in one row" "$rs" check demo
"$here/log.sh" .dflow/demo.tsv correction "a" "b" "commit ${c1:0:7}" ok
expect 0 "older commit logged last" "$rs" check demo
git reset -q --hard "$c1^"; expect 1 "HEAD behind logged commit" "$rs" check demo
git reset -q --hard "$c1"
# an unlogged commit before a logged one is still found: C1 unlogged, C2 logged -> 3, UNLOGGED C1
cp .dflow/demo.tsv "$t/log"
echo e >> src/a.py; git commit -qam four; u1=$(git rev-parse HEAD); echo f >> src/a.py; git commit -qam five; u2=$(git rev-parse HEAD)
"$here/log.sh" .dflow/demo.tsv round "a" "b" "commit $u2" ok
out=$("$rs" check demo); [ $? = 3 ] && [ "$(echo "$out" | grep '^UNLOGGED')" = "UNLOGGED $u1" ] && ok || bad "unlogged commit before a logged one: $out"
cp "$t/log" .dflow/demo.tsv; git reset -q --hard "$c1"

# R7: a 多线 land (parallel.sh land of the verified source commit, then the commit on the run branch)
# logged as "commit <new sha> from <source sha>" is a logged commit for the next round's check;
# the bare mapping "<source> -> <new>" is not
cp .dflow/demo.tsv "$t/log"
git worktree add -q -b dflow-unit/demo-u "$t/wu" "$c1"
( cd "$t/wu"; echo u > src/u.py; git add -A; git commit -qm "unit u" ); src=$(git -C "$t/wu" rev-parse HEAD)
printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\nu\t-\tsrc/u.py\tdispatched\t%s\t-\tdflow-unit/demo-u\t-\t0\t-\n' "$c1" > .dflow/demo.units.tsv
expect 0 "land u at its verified sha" "$here/parallel.sh" land demo u "$src"
git commit -qm "land u"; new=$(git rev-parse HEAD)
"$here/log.sh" .dflow/demo.tsv round "落地 u" "来源已验收" "$src -> $new" ok
out=$("$rs" check demo); [ $? = 3 ] && echo "$out" | grep -qx "UNLOGGED $new" && ok || bad "a bare mapping counted as logged: $out"
"$here/log.sh" .dflow/demo.tsv round "落地 u" "来源已验收" "commit $new from $src" ok
out=$("$rs" check demo); rc=$?
[ $rc = 0 ] && ! echo "$out" | grep -q UNLOGGED && ok || bad "landed commit logged as commit <new> from <source>: $rc $out"
cp "$t/log" .dflow/demo.tsv; git reset -q --hard "$c1"; rm -f .dflow/demo.units.tsv .dflow/demo.landed
git worktree remove --force "$t/wu"; git branch -D -q dflow-unit/demo-u

# wrong branch
git checkout -qb other; expect 1 "wrong branch" "$rs" check demo; git checkout -q dflow/demo

# scope: protected and outside files
echo z > README.md; echo u >> tests/t.py; git add -A; git commit -qm scope
out=$("$rs" scope demo); [ $? = 1 ] && ok || bad "scope exit"
echo "$out" | grep -q 'PROTECTED tests/t.py' && ok || bad "protected not reported: $out"
echo "$out" | grep -q 'OUTSIDE README.md' && ok || bad "outside not reported: $out"
echo "$out" | grep -q 'src/a.py' && bad "allowed file reported" || ok
git reset -q --hard "$c1"

# deadline passed -> exit 4
sed -i '' "s/^deadline: .*/deadline: 2000-01-01T00:00:00Z/" .dflow/demo.md
sed -i '' "s/^manifest_sha256: .*/manifest_sha256: $(shasum -a 256 .dflow/demo.md | cut -d' ' -f1)/" .dflow/demo.lock/lease
expect 4 "deadline passed" "$rs" check demo
cp "$t/m" .dflow/demo.md; sed -i '' "s/^manifest_sha256: .*/manifest_sha256: $(shasum -a 256 .dflow/demo.md | cut -d' ' -f1)/" .dflow/demo.lock/lease

# caffeinate started, recorded, and only that pid is stopped on release
if command -v caffeinate >/dev/null; then
    caffeinate -i -t 120 & other=$!
    expect 0 "caffeinate" "$rs" caffeinate demo
    mine=$(sed -n 's/^caffeinate_pid: //p' .dflow/demo.lock/lease)
    ps -o comm= -p "$mine" | grep -q caffeinate && ok || bad "caffeinate not running"
    [ "$(ps -o pgid= -p "$mine" | tr -d ' ')" = "$mine" ] && ok || bad "caffeinate not in its own session (a host that kills the call's group would stop it)"
    expect 0 "release" "$rs" release demo
    sleep 0.3; kill -0 "$mine" 2>/dev/null && bad "own caffeinate still running" || ok
    kill -0 "$other" 2>/dev/null && ok || bad "other caffeinate was stopped"
    kill "$other" 2>/dev/null
    [ -d .dflow/demo.lock ] && bad "lock left after release" || ok
fi
# host detection: under a process named codex, the lease takes $CODEX_THREAD_ID and that pid
rm -rf .dflow/demo.lock
# A copy of a shell named codex/claude stands in for the agent; macOS kills copies of /bin
# binaries, so take the first bash on PATH that still runs when copied, else skip.
mkdir -p "$t/bin"; fake=""
for b in $(which -a bash) /opt/homebrew/bin/bash /usr/local/bin/bash; do
    cp "$b" "$t/bin/codex" 2>/dev/null && [ "$("$t/bin/codex" -c 'echo ok' 2>/dev/null)" = ok ] && { fake=$b; break; }
done
if [ -z "$fake" ]; then echo "skip host-detection tests: no copyable bash"; else
cp "$fake" "$t/bin/claude"
out=$(env -u DFLOW_SESSION_ID -u DFLOW_AGENT_PID CODEX_THREAD_ID=th-1 CLAUDE_CODE_SESSION_ID=inherited \
    "$t/bin/codex" -c "\"$rs\" claim demo; echo pid=\$\$; true" 2>&1)
lp=$(sed -n 's/^pid: //p' .dflow/demo.lock/lease)
grep -q '^session: th-1$' .dflow/demo.lock/lease && ok || bad "codex host: lease session not CODEX_THREAD_ID: $out"
[ "pid=$lp" = "$(printf '%s\n' "$out" | grep '^pid=')" ] && ok || bad "codex host: lease pid $lp is not the codex process ($out)"
rm -rf .dflow/demo.lock
out=$(env -u DFLOW_SESSION_ID -u DFLOW_AGENT_PID -u CLAUDE_PID CODEX_THREAD_ID=inherited CLAUDE_CODE_SESSION_ID=cs-1 \
    "$t/bin/claude" -c "\"$rs\" claim demo; true" 2>&1)
grep -q '^session: cs-1$' .dflow/demo.lock/lease && ok || bad "claude host: lease session not CLAUDE_CODE_SESSION_ID: $out"
# a live codex owner blocks a takeover like a live claude one
"$t/bin/codex" -c 'sleep 30; true' & pids+=($!); xp=$!
sed -i '' "s/^pid: .*/pid: $xp/; s/^session: .*/session: other/" .dflow/demo.lock/lease
DFLOW_OWNER_COMM=none expect 1 "claim refused while a codex owner is alive" "$rs" claim demo
kill "$xp" 2>/dev/null; rm -rf .dflow/demo.lock
fi
echo "run-state-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
