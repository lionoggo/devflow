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
rm -rf .dflow/demo.lock; expect 0 "claim again" "$rs" claim demo

# manifest change detected
cp .dflow/demo.md "$t/m"; echo extra >> .dflow/demo.md
expect 1 "manifest changed" "$rs" check demo
cp "$t/m" .dflow/demo.md

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
