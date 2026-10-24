#!/usr/bin/env bash
# Tests for lines.sh against a throwaway repo: init on an old table, line set, receipts, the ledger
# (pass only on the same sha), status, and machine-wide resource locks (mutual exclusion across
# working directories, one winner when a stale lock is taken over concurrently).
set -u
here=$(cd "$(dirname "$0")" && pwd); ln="$here/lines.sh"; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
expect() { local want=$1 desc=$2; shift 2; out=$("$@" 2>&1); got=$?; [ "$got" = "$want" ] && ok || bad "$desc: exit $got, want $want: $out"; }
t=$(mktemp -d "${TMPDIR:-/tmp}/lines-test.XXXXXX"); pids=()
trap 'for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$t"' EXIT
export DFLOW_LOCK_DIR="$t/locks"
r="$t/repo"; git init -q "$r"; cd "$r"; git config user.email t@t; git config user.name t
echo a > a.txt; git add -A; git commit -qm base; base=$(git rev-parse HEAD)
mkdir -p .dflow
printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\n' > .dflow/demo.units.tsv
printf 'a\t-\ta.txt\tdispatched\t%s\t-\twa\t-\t0\t-\n' "$base" >> .dflow/demo.units.tsv

# init on an old 10-column table: six columns added, old rows padded with "-", ledger header, standing.md
expect 0 "init" "$ln" init demo
[ "$(head -1 .dflow/demo.units.tsv)" = "$(printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\tcarrier\tmodel\tattempt\tbrief\treport\tprogress_at')" ] && ok || bad "header: $(head -1 .dflow/demo.units.tsv)"
[ "$(awk -F'\t' 'NR == 2 { print NF, $7, $16 }' .dflow/demo.units.tsv)" = "16 wa -" ] && ok || bad "old row not padded: $(sed -n 2p .dflow/demo.units.tsv)"
[ "$(head -1 .dflow/demo/ledger.tsv)" = "$(printf 'id\tattempt\tsha\tresult\tevidence_type\tverifier\tevidence\tts')" ] && [ -f .dflow/demo/standing.md ] && ok || bad "ledger header or standing.md"
grep -qxF .dflow/ "$(git rev-parse --git-path info/exclude)" && ok || bad ".dflow/ not excluded"
expect 0 "init again is a no-op" "$ln" init demo
[ "$(head -1 .dflow/demo.units.tsv | tr '\t' '\n' | grep -c attempt)" = 1 ] && ok || bad "init added columns twice"
# the old table still works for parallel.sh after init
expect 1 "parallel.sh reads the widened table" "$here/parallel.sh" scope demo a   # branch wa does not exist: refused, not misread
echo "$out" | grep -q "branch wa not found" && ok || bad "parallel.sh misread the widened table: $out"

# line set by header name; unknown column refused; a new id adds a row
expect 0 "line set" "$ln" line set demo a carrier=headless model=codex attempt=1 progress_at=2026-10-24T00:00:00Z
[ "$(awk -F'\t' 'NR == 2 { print $4, $11, $12, $13, $16 }' .dflow/demo.units.tsv)" = "dispatched headless codex 1 2026-10-24T00:00:00Z" ] && ok || bad "line set: $(sed -n 2p .dflow/demo.units.tsv)"
expect 1 "unknown column" "$ln" line set demo a colour=red
expect 0 "new line" "$ln" line set demo b state=planned carrier=visible attempt=1
[ "$(awk -F'\t' '$1 == "b" { print NF, $4, $11, $7 }' .dflow/demo.units.tsv)" = "16 planned visible -" ] && ok || bad "new row: $(grep '^b' .dflow/demo.units.tsv)"
expect 2 "line set without assignment" "$ln" line set demo a

# receipts: valid, wrong attempt inside the file, malformed, missing
mkdir -p .dflow/demo/reports
echo "RECEIPT a 1 done $base" > .dflow/demo/reports/a-1.md
out=$("$ln" receipt demo a 1); [ $? = 0 ] && [ "$out" = "done $base" ] && ok || bad "valid receipt: $out"
echo "RECEIPT a 1 done $base" > .dflow/demo/reports/a-2.md
expect 1 "an old attempt's receipt under the new attempt's name" "$ln" receipt demo a 2
echo "RECEIPT a 2 finished $base" > .dflow/demo/reports/a-2.md
expect 1 "unknown state" "$ln" receipt demo a 2
echo "done" > .dflow/demo/reports/a-3.md
expect 1 "malformed receipt" "$ln" receipt demo a 3
expect 1 "missing receipt" "$ln" receipt demo a 4
echo "RECEIPT b 1 done docs/review.md" > .dflow/demo/reports/b-1.md
out=$("$ln" receipt demo b 1); [ "$out" = "done docs/review.md" ] && ok || bad "read-only receipt with a path: $out"

# ledger: pass only on the same sha; review never counts; self only with single-command evidence;
# a fix on a new sha needs its own pass; a later fail on a sha revokes its pass
git checkout -qb wa; echo fix1 >> a.txt; git commit -qam "a try 1"; s1=$(git rev-parse HEAD)
echo fix2 >> a.txt; git commit -qam "a fix"; s2=$(git rev-parse HEAD); git checkout -q -
expect 2 "no verdict" "$ln" ledger check demo a "$s1"
echo "$out" | grep -q '^NOT-PASSED' && ok || bad "NOT-PASSED not printed: $out"
expect 0 "record review pass" "$ln" ledger record demo a 1 "$s1" pass review codex "review.out"
expect 2 "review pass does not count" "$ln" ledger check demo a "$s1"
expect 0 "record self pass" "$ln" ledger record demo a 1 "$s1" pass self worker "ran tests"
expect 2 "self pass without single-command" "$ln" ledger check demo a "$s1"
expect 0 "record behavior fail" "$ln" ledger record demo a 1 "$s1" fail behavior claude "repro.log"
expect 2 "fail" "$ln" ledger check demo a "$s1"
expect 0 "record pass on the fix" "$ln" ledger record demo a 2 "${s2:0:10}" pass behavior claude "repro2.log"
expect 0 "pass on the fix sha (short sha recorded, full sha checked)" "$ln" ledger check demo a "$s2"
expect 2 "the old sha is still not passed" "$ln" ledger check demo a "$s1"
expect 2 "a pass for another line does not count" "$ln" ledger check demo b "$s2"
echo fix3 >> a.txt; git commit -qam "a fix 3"; s3=$(git rev-parse HEAD); git reset -q --hard HEAD~1
expect 2 "a newer sha after the pass needs its own" "$ln" ledger check demo a "$s3"
echo "$out" | grep -q "pass recorded on" && ok || bad "other-sha pass not named: $out"
expect 0 "self pass with single-command evidence" "$ln" ledger record demo a 3 "$s3" pass self worker "single-command: make check"
expect 0 "single-command self pass counts" "$ln" ledger check demo a "$s3"
expect 0 "later fail" "$ln" ledger record demo a 3 "$s3" fail test codex "ci.log"
expect 2 "a later fail revokes the pass" "$ln" ledger check demo a "$s3"
expect 1 "bad result" "$ln" ledger record demo a 1 "$s1" ok test x y
expect 1 "bad evidence type" "$ln" ledger record demo a 1 "$s1" pass vibes x y
expect 0 "blocked receipt line recorded" "$ln" ledger record demo b 1 docs/review.md blocked review codex "b-1.md"
expect 2 "blocked is not pass" "$ln" ledger check demo b docs/review.md

# status: board from table, ledger and receipts; open gates from the decision log; changed lines
"$here/log.sh" .dflow/demo.tsv gate "接口用 v1 还是 v2" "两者都可" "-" "默认 v1" >/dev/null
"$here/log.sh" .dflow/demo.tsv gate "要不要删旧表" "影响迁移" "-" "默认保留" >/dev/null
"$here/log.sh" .dflow/demo.tsv gate "要不要删旧表" "用户说保留" "-" closed >/dev/null
"$ln" line set demo a attempt=2 >/dev/null; echo "RECEIPT a 2 done $s2" > .dflow/demo/reports/a-2.md
out=$("$ln" status demo); rc=$?
[ $rc = 0 ] && [ "$(echo "$out" | wc -l | tr -d ' ')" = 3 ] && ok || bad "status summary: $rc $out"
echo "$out" | grep -q '^counts: 2 lines; .*dispatched 1.*receipts 2; passed 1$' && ok || bad "counts: $out"
echo "$out" | grep -qx 'changed: a b' && ok || bad "first status changed: $out"
echo "$out" | grep -qx 'gates open: 1' && ok || bad "gates: $out"
grep -q '接口用 v1 还是 v2' .dflow/demo/status.md && ! grep -q '要不要删旧表' .dflow/demo/status.md && ok || bad "gate list: $(cat .dflow/demo/status.md)"
grep -q "^| a | dispatched | headless | codex | 2 | 2026-10-24T00:00:00Z | done $s2 | pass @$s2 |" .dflow/demo/status.md && ok || bad "row a: $(cat .dflow/demo/status.md)"
out=$("$ln" status demo); echo "$out" | grep -qx 'changed: none' && ok || bad "second status changed: $out"
"$ln" line set demo b state=blocked >/dev/null
out=$("$ln" status demo); echo "$out" | grep -qx 'changed: b' && ok || bad "changed after edit: $out"
# a 10-column table without init still renders (missing columns as "-")
printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\nz\t-\tx\tplanned\t-\t-\t-\t-\t0\t-\n' > .dflow/old.units.tsv
mkdir -p .dflow/old; printf 'id\tattempt\tsha\tresult\tevidence_type\tverifier\tevidence\tts\n' > .dflow/old/ledger.tsv
out=$("$ln" status old); [ $? = 0 ] && grep -q '^| z | planned | - | - | - | - | - | - |' .dflow/old/status.md && ok || bad "old table status: $out $(cat .dflow/old/status.md)"

# concurrent writers keep every row (write lock + atomic replace)
rp=(); for i in 1 2 3 4 5 6 7 8; do "$ln" ledger record demo c 1 "$base" pass test w$i "e$i" >/dev/null & rp+=($!); done; wait "${rp[@]}"
[ "$(grep -c '^c	' .dflow/demo/ledger.tsv)" = 8 ] && ok || bad "concurrent records: $(grep -c '^c	' .dflow/demo/ledger.tsv) of 8"
[ ! -e .dflow/demo/.lock ] && ok || bad "write lock left behind"

# resource locks: machine-wide, so two working directories contend for the same one
mkdir -p "$t/wt1" "$t/wt2"
sleep 60 & pids+=($!); p1=$!; sleep 60 & pids+=($!); p2=$!
out=$(cd "$t/wt1" && "$ln" lock acquire gui demo/a/1 "$p1"); [ $? = 0 ] && ok || bad "acquire from wt1: $out"
out=$(cd "$t/wt2" && "$ln" lock acquire gui demo/b/1 "$p2"); [ $? = 1 ] && echo "$out" | grep -q "held by demo/a/1" && ok || bad "second holder not refused: $out"
out=$(cd "$t/wt1" && "$ln" lock acquire gui demo/a/1 "$p1"); [ $? = 0 ] && ok || bad "re-acquire by the holder: $out"
out=$("$ln" lock show gui); echo "$out" | grep -qx "attempt: demo/a/1" && echo "$out" | grep -qx "pid: $p1" && echo "$out" | grep -q "^command: sleep 60" && echo "$out" | grep -qx "state: alive" && ok || bad "show: $out"
expect 1 "release by another attempt" "$ln" lock release gui demo/b/1
expect 0 "release by the holder" "$ln" lock release gui demo/a/1
expect 0 "show free" "$ln" lock show gui; [ "$out" = "free gui" ] && ok || bad "show after release: $out"
expect 1 "acquire for a pid that is not running" "$ln" lock acquire gui demo/a/1 999999
# held by a process that is gone (stop confirmed): another attempt takes it over
sh -c 'exit 0' & dead=$!; wait "$dead"
mkdir -p "$DFLOW_LOCK_DIR/gui"; printf 'attempt: demo/a/1\npid: %s\ncommand: sleep 60\nsince: 2026-10-24T00:00:00Z\n' "$dead" > "$DFLOW_LOCK_DIR/gui/holder"
out=$("$ln" lock acquire gui demo/b/1 "$p2"); [ $? = 0 ] && echo "$out" | grep -q "took over" && ok || bad "takeover of a gone holder: $out"
# a live pid that now runs another command (pid reused) is gone as a holder
printf 'attempt: demo/a/1\npid: %s\ncommand: some-old-command\nsince: 2026-10-24T00:00:00Z\n' "$p1" > "$DFLOW_LOCK_DIR/gui/holder"
out=$("$ln" lock acquire gui demo/b/1 "$p2"); [ $? = 0 ] && ok || bad "takeover of a reused pid: $out"
# stop not confirmed: the holder still runs, so its lock is not reused
printf 'attempt: demo/a/1\npid: %s\ncommand: %s\nsince: 2026-10-24T00:00:00Z\n' "$p1" "$(ps -ww -o command= -p "$p1")" > "$DFLOW_LOCK_DIR/gui/holder"
expect 1 "unconfirmed stop keeps the lock" "$ln" lock acquire gui demo/a/2 "$p2"
# concurrent takeovers of one stale lock: exactly one winner, the holder names it, nothing left behind
printf 'attempt: demo/a/1\npid: %s\ncommand: sleep 60\nsince: 2026-10-24T00:00:00Z\n' "$dead" > "$DFLOW_LOCK_DIR/gui/holder"
: > "$t/won"; rp=()
for i in 1 2 3 4 5 6 7 8; do (cd "$t/wt$(( i % 2 + 1 ))" && "$ln" lock acquire gui "demo/t$i/1" "$p2" >/dev/null 2>&1 && echo "demo/t$i/1" >> "$t/won") & rp+=($!); done; wait "${rp[@]}"
[ "$(wc -l < "$t/won" | tr -d ' ')" = 1 ] && grep -qx "attempt: $(cat "$t/won")" "$DFLOW_LOCK_DIR/gui/holder" && ok || bad "concurrent takeovers: winners $(tr '\n' ' ' < "$t/won"); holder $(cat "$DFLOW_LOCK_DIR/gui/holder")"
[ -z "$(ls -d "$DFLOW_LOCK_DIR"/gui.* 2>/dev/null)" ] && ok || bad "takeover left $(ls -d "$DFLOW_LOCK_DIR"/gui.*)"
kill "$p1" "$p2" 2>/dev/null

expect 2 "usage" "$ln"
expect 1 "bad slug" "$ln" status "../x"
expect 1 "bad resource" "$ln" lock show "../x"
echo "lines-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
