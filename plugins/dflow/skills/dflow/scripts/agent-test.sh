#!/usr/bin/env bash
# Tests for agent.sh in a throwaway repo and worktree: the worker runs in its worktree with the brief on
# stdin; done means process ended plus a receipt for this id and attempt (intermediate commits are not
# done, an old attempt's receipt does not count, a read-only delivery counts); repeated or concurrent
# starts of one attempt are refused without overwriting; the brief must name the attempt; peek never
# signals; stop checks identity first. DFLOW_AGENT_CMD or stub binaries stand in
# for claude and codex.
set -u
here=$(cd "$(dirname "$0")" && pwd); ag="$here/agent.sh"; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
t=$(mktemp -d "${TMPDIR:-/tmp}/agent-test.XXXXXX"); mine=()
trap 'for p in "${mine[@]}"; do kill -9 -- -"$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done; rm -rf "$t"' EXIT
r="$t/repo"; git init -q "$r"; cd "$r"; git config user.email t@t; git config user.name t
echo a > a.txt; git add -A; git commit -qm base
git worktree add -q -b wa "$t/wa"; "$here/lines.sh" init demo >/dev/null
wt=$(cd "$t/wa" && pwd -P)
bf() { printf 'dflow 线 demo/a/%s\n做这件事\n' "$1" > ".dflow/demo/briefs/a-$1.md"; echo ".dflow/demo/briefs/a-$1.md"; }
rep=.dflow/demo/reports
run() { # run <attempt> <shell command>: start with DFLOW_AGENT_CMD, record the pid
    local p; p=$(DFLOW_AGENT_CMD=$2 "$ag" start demo a "$1" "$(bf "$1")" "$t/wa"); local rc=$?
    [ -n "$p" ] && mine+=("$p"); echo "$p"; return $rc
}

# 1: commits in the worktree, then exits without a receipt -> not delivered
s=$(date +%s)
pid=$(run 1 'echo "brief: $(head -1)"; echo "cwd: $(pwd -P)"; echo "line: $DFLOW_LINE"; echo x >> a.txt; git commit -qam mid; sleep 5')
[ $(( $(date +%s) - s )) -lt 2 ] && [ -n "$pid" ] && ok || bad "start blocked or printed no pid"
out=$("$ag" wait demo a 1 1); [ $? = 3 ] && [ "$out" = running ] && ok || bad "wait while running: $out"
out=$("$ag" wait demo a 1 20); [ $? = 1 ] && [ "$out" = "exited without receipt" ] && ok || bad "mid commit counted as done: $out"
o=.dflow/demo/run/a-1.out
grep -qx "brief: dflow 线 demo/a/1" "$o" && grep -qx "cwd: $wt" "$o" && grep -qx "line: demo/a/1" "$o" && ok || bad "brief, cwd or env: $(cat "$o")"
[ "$(git -C "$t/wa" log -1 --format=%s)" = mid ] && ok || bad "worker did not commit in its worktree"
# an ended attempt is not started again: one file per attempt
out=$(run 1 'echo again'); [ $? = 1 ] && echo "$out" | grep -q "start attempt 2" && grep -qx "line: demo/a/1" "$o" && ok || bad "restart of an ended attempt: $out"

# 2: an old attempt's receipt (a-1.md, or a-2.md naming attempt 1) never stands for attempt 2
echo "RECEIPT a 1 done $(git -C "$t/wa" rev-parse HEAD)" > "$rep/a-1.md"
pid=$(run 2 'exit 0')
out=$("$ag" wait demo a 2 20); [ "$out" = "exited without receipt" ] && ok || bad "attempt 1 receipt used for attempt 2: $out"
pid=$(run 3 'echo "RECEIPT a 1 done abc1234" > "$DFLOW_RECEIPT"')
out=$("$ag" wait demo a 3 20); [ "$out" = "exited without receipt" ] && ok || bad "receipt naming another attempt: $out"

# 4: a done receipt with a sha; 5: a read-only delivery (a path); 6: blocked is delivered, as blocked
pid=$(run 4 'git commit -q --allow-empty -m done; echo "RECEIPT a 4 done $(git rev-parse HEAD)" > "$DFLOW_RECEIPT"')
out=$("$ag" wait demo a 4 20); [ $? = 0 ] && [ "$out" = "delivered done $(git -C "$t/wa" rev-parse HEAD)" ] && ok || bad "done receipt: $out"
pid=$(run 5 'printf "RECEIPT a 5 done docs/audit.md\n跑过：无\n" > "$DFLOW_RECEIPT"')
out=$("$ag" wait demo a 5 20); [ $? = 0 ] && [ "$out" = "delivered done docs/audit.md" ] && ok || bad "read-only delivery: $out"
pid=$(run 6 'echo "RECEIPT a 6 blocked -" > "$DFLOW_RECEIPT"')
out=$("$ag" wait demo a 6 20); [ "$out" = "delivered blocked -" ] && ok || bad "blocked receipt: $out"
# a receipt while the process still runs is not delivered yet
pid=$(run 7 'echo "RECEIPT a 7 done x" > "$DFLOW_RECEIPT"; sleep 30')
sleep 0.5; out=$("$ag" wait demo a 7 1); [ $? = 3 ] && [ "$out" = running ] && ok || bad "receipt before exit: $out"

# a second start of a running attempt is refused and overwrites nothing
rec=$(cat .dflow/demo/run/a-7.out.pid)
out=$(run 7 'echo clobber'); [ $? = 1 ] && [ "$(cat .dflow/demo/run/a-7.out.pid)" = "$rec" ] && ! grep -q clobber .dflow/demo/run/a-7.out && ok || bad "second start of a running attempt: $out"
# stop: identity checked first; a foreign pid record is never signalled
cp .dflow/demo/run/a-7.out.pid "$t/a7.pid"
python3 -I -c 'import os, time; os.setsid(); time.sleep(30)' & other=$!; disown "$other"; mine+=("$other"); sleep 0.3
echo "$other $(date +%s)" > .dflow/demo/run/a-7.out.pid
out=$("$ag" stop demo a 7); [ $? = 1 ] && case $out in "not stopped: "*) true ;; *) false ;; esac && kill -0 "$other" 2>/dev/null && kill -0 "$pid" 2>/dev/null && ok || bad "stop with a foreign pid: $out"
cp "$t/a7.pid" .dflow/demo/run/a-7.out.pid
out=$("$ag" stop demo a 7); [ $? = 0 ] && [ "$out" = "ok stopped" ] && ! kill -0 -- -"$pid" 2>/dev/null && ok || bad "stop: $out"
out=$("$ag" wait demo a 7 1); [ "$out" = "ended lost" ] && ok || bad "wait after stop: $out"

# the real commands, through stubs on PATH: model, flags, worktree, and brief on stdin
mkdir -p "$t/bin"
for m in claude codex; do printf '#!/bin/sh\necho "%s $*"; echo "cwd $(pwd -P)"; cat\n' "$m" > "$t/bin/$m"; chmod +x "$t/bin/$m"; done
p=$(PATH="$t/bin:$PATH" "$ag" start demo a 8 "$(bf 8)" "$t/wa" claude); mine+=("$p")
"$ag" wait demo a 8 20 >/dev/null
grep -qx "claude -p --dangerously-skip-permissions" .dflow/demo/run/a-8.out && grep -qx "cwd $wt" .dflow/demo/run/a-8.out && grep -qx "做这件事" .dflow/demo/run/a-8.out && ok || bad "claude command: $(cat .dflow/demo/run/a-8.out)"
p=$(PATH="$t/bin:$PATH" "$ag" start demo a 9 "$(bf 9)" "$t/wa" codex); mine+=("$p")
"$ag" wait demo a 9 20 >/dev/null
grep -qx "codex exec --dangerously-bypass-approvals-and-sandbox -C $wt -" .dflow/demo/run/a-9.out && grep -qx "做这件事" .dflow/demo/run/a-9.out && ok || bad "codex command: $(cat .dflow/demo/run/a-9.out)"
p=$(PATH="$t/bin:$PATH" "$ag" start demo a 10 "$(bf 10)" "$t/wa"); mine+=("$p")
"$ag" wait demo a 10 20 >/dev/null
grep -Eq '^(claude -p --dangerously-skip-permissions|codex exec --dangerously-bypass-approvals-and-sandbox -C .* -)$' .dflow/demo/run/a-10.out && ok || bad "default model: $(cat .dflow/demo/run/a-10.out)"

out=$("$ag" start demo a 11 "$(bf 11)" "$t/nowhere" 2>&1); [ $? = 1 ] && ok || bad "missing worktree: $out"
"$ag" start demo a 0 "$(bf 1)" "$t/wa" >/dev/null 2>&1; [ $? = 1 ] && ok || bad "attempt 0 accepted"
"$ag" wait >/dev/null 2>&1; [ $? = 2 ] && ok || bad "usage"

# the brief must name this slug, id and attempt: a brief for another attempt is refused, nothing claimed
bf 1 > /dev/null; cp .dflow/demo/briefs/a-1.md .dflow/demo/briefs/a-12.md
out=$(DFLOW_AGENT_CMD='echo ran' "$ag" start demo a 12 .dflow/demo/briefs/a-12.md "$t/wa" 2>&1); [ $? = 1 ] && echo "$out" | grep -q "not \"dflow 线 demo/a/12\"" && [ ! -e .dflow/demo/run/a-12.out ] && [ ! -e .dflow/demo/run/a-12.claim ] && ok || bad "brief for another attempt accepted: $out"
printf '做这件事\n' > .dflow/demo/briefs/a-12.md
out=$(DFLOW_AGENT_CMD='echo ran' "$ag" start demo a 12 .dflow/demo/briefs/a-12.md "$t/wa" 2>&1); [ $? = 1 ] && [ ! -e .dflow/demo/run/a-12.out ] && ok || bad "brief without the line marker accepted: $out"
# concurrent starts of one attempt: exactly one starts, the others overwrite nothing
b13=$(bf 13); : > "$t/won13"; rp=()
for i in 1 2 3 4 5 6; do ( p=$(DFLOW_AGENT_CMD="echo starter-$i; sleep 30" "$ag" start demo a 13 "$b13" "$t/wa" 2>/dev/null) && echo "$i $p" >> "$t/won13" ) & rp+=($!); done; wait "${rp[@]}"
read -r wi wp < "$t/won13"; [ -n "${wp:-}" ] && mine+=("$wp"); sleep 0.5
[ "$(wc -l < "$t/won13" | tr -d ' ')" = 1 ] && [ "$(head -1 .dflow/demo/run/a-13.out.pid | cut -d' ' -f1)" = "$wp" ] && [ "$(cat .dflow/demo/run/a-13.out)" = "starter-$wi" ] && ok || bad "concurrent starts: winners $(tr '\n' ';' < "$t/won13"); out $(cat .dflow/demo/run/a-13.out)"
# peek looks without signalling: no limit, the worker keeps running; an ended attempt reads like wait
out=$("$ag" peek demo a 13); [ $? = 3 ] && [ "$out" = running ] && kill -0 "$wp" 2>/dev/null && ok || bad "peek running: $out"
"$ag" stop demo a 13 >/dev/null
out=$("$ag" peek demo a 4); [ $? = 0 ] && [ "$out" = "delivered done $(git -C "$t/wa" rev-parse HEAD)" ] && ok || bad "peek delivered: $out"
out=$("$ag" peek demo a 2); [ $? = 1 ] && [ "$out" = "exited without receipt" ] && ok || bad "peek without receipt: $out"
# peek of a run over any limit, with no ps: reported running, never signalled
pid=$(run 14 'sleep 30'); sleep 0.3
mkdir -p "$t/nops"; printf '#!/bin/sh\necho "ps: operation not permitted" >&2; exit 1\n' > "$t/nops/ps"; chmod +x "$t/nops/ps"
out=$(PATH="$t/nops:$PATH" "$ag" peek demo a 14); [ "$out" = running ] && kill -0 "$pid" 2>/dev/null && ok || bad "peek without ps: $out"
out=$(PATH="$t/nops:$PATH" "$ag" wait demo a 14 1 1); case $out in "ended timeout, not stopped"*) kill -0 "$pid" 2>/dev/null && ok || bad "no ps: worker stopped at the limit";; *) bad "no ps at the limit: $out";; esac
"$ag" stop demo a 14 >/dev/null
echo "agent-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
