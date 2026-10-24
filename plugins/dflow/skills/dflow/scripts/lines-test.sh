#!/usr/bin/env bash
# Tests for lines.sh against a throwaway repo: init on an old table, line set, receipts, the ledger
# (pass only on the same full sha; a verifier's verdict outranks a self pass; self needs the brief's
# 单命令验证), status (and the read-only --print), and machine-wide resource locks (mutual exclusion
# across working directories, release only with the holder's token, one winner when a stale lock is
# taken over concurrently, and no acquire while a release has the lock moved aside).
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
# a report still being written (<report>.tmp) is not a receipt; only the final name counts
echo "RECEIPT a 5 done $base" > .dflow/demo/reports/a-5.md.tmp
expect 1 "a receipt still in .tmp" "$ln" receipt demo a 5

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
expect 2 "single-command self pass without the brief's permission" "$ln" ledger check demo a "$s3"
echo "$out" | grep -q "单命令验证" && ok || bad "brief permission not named: $out"
# R4: only the structured line "验证<blanks>单命令验证：<command>" in that attempt's brief allows it
printf 'dflow 线 demo/a/3\n验证：禁止单命令验证；必须另派验收线\n' > .dflow/demo/briefs/a-3.md
expect 2 "a brief that forbids 单命令验证" "$ln" ledger check demo a "$s3"
printf 'dflow 线 demo/a/3\n说明：小改动可以单命令验证，但这次不行。\n验证     另派验收线\n' > .dflow/demo/briefs/a-3.md
expect 2 "单命令验证 only in prose" "$ln" ledger check demo a "$s3"
printf 'dflow 线 demo/a/3\n  验证 单命令验证：make check\n验证 单命令验证：\n' > .dflow/demo/briefs/a-3.md
expect 2 "the line indented, or without a command" "$ln" ledger check demo a "$s3"
printf 'dflow 线 demo/a/2\n验证     单命令验证：make check\n' > .dflow/demo/briefs/a-3.md
expect 2 "the right line in another attempt's brief" "$ln" ledger check demo a "$s3"
printf 'dflow 线 demo/a/3\n目标     修 a\n验证     单命令验证：make check\n' > .dflow/demo/briefs/a-3.md
expect 0 "single-command self pass counts with the brief's 验证 line" "$ln" ledger check demo a "$s3"
expect 0 "later fail" "$ln" ledger record demo a 3 "$s3" fail test codex "ci.log"
expect 2 "a later fail revokes the pass" "$ln" ledger check demo a "$s3"
# a verifier's fail is not undone by a self pass appended after it
expect 0 "self pass after the fail" "$ln" ledger record demo a 3 "$s3" pass self worker "single-command: make check"
expect 2 "self pass after a verifier's fail" "$ln" ledger check demo a "$s3"
echo "$out" | grep -q "fail (test, codex)" && ok || bad "verifier's fail not named: $out"
# the latest verifier row decides; a review pass is ignored (it can fail a sha, never pass it)
expect 0 "behavior pass after the fail" "$ln" ledger record demo a 3 "$s3" pass behavior claude "repro3.log"
expect 0 "the latest verifier pass decides" "$ln" ledger check demo a "$s3"
expect 0 "review pass after it" "$ln" ledger record demo a 3 "$s3" pass review codex "r.out"
expect 0 "a review pass neither counts nor overrides" "$ln" ledger check demo a "$s3"
expect 0 "review fail after it" "$ln" ledger record demo a 3 "$s3" fail review codex "r2.out"
expect 2 "a review fail overrides the behavior pass" "$ln" ledger check demo a "$s3"
# shas: stored in full; a path, an unknown or an ambiguous prefix is refused in record and check
[ "$(awk -F'\t' '$1 == "a" && $2 == 2 { print $3 }' .dflow/demo/ledger.tsv)" = "$s2" ] && ok || bad "short sha not stored in full: $(cat .dflow/demo/ledger.tsv)"
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
e=$(git hash-object -t tree -w /dev/null); x3=$(git commit-tree "$e" -m n3); x48=$(git commit-tree "$e" -m n48)
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
[ "${x3:0:4}" = "${x48:0:4}" ] && [ "$x3" != "$x48" ] && ok || bad "test setup: $x3 and $x48 should share 4 hex digits"
expect 1 "ambiguous prefix in record" "$ln" ledger record demo a 3 "${x3:0:4}" pass behavior claude x
expect 1 "ambiguous prefix in check" "$ln" ledger check demo a "${x3:0:4}"
expect 0 "a unique prefix of the same commit" "$ln" ledger record demo a 3 "${x3:0:6}" fail behavior claude x
expect 1 "unknown sha" "$ln" ledger record demo a 3 abcdef0 pass behavior claude x
expect 1 "unknown sha in check" "$ln" ledger check demo a abcdef0
expect 1 "a branch name is not a sha" "$ln" ledger record demo a 3 wa pass behavior claude x
expect 1 "bad result" "$ln" ledger record demo a 1 "$s1" ok test x y
expect 1 "bad evidence type" "$ln" ledger record demo a 1 "$s1" pass vibes x y
expect 1 "a path is not a commit" "$ln" ledger record demo b 1 docs/review.md pass behavior codex "b-1.md"
expect 0 "blocked recorded" "$ln" ledger record demo b 1 "$s1" blocked behavior codex "b-1.md"
expect 2 "blocked is not pass" "$ln" ledger check demo b "$s1"

# status: board from table, ledger and receipts; open gates from the decision log; changed lines
"$here/log.sh" .dflow/demo.tsv gate "接口用 v1 还是 v2" "两者都可" "-" "默认 v1" >/dev/null
"$here/log.sh" .dflow/demo.tsv gate "要不要删旧表" "影响迁移" "-" "默认保留" >/dev/null
"$here/log.sh" .dflow/demo.tsv gate "要不要删旧表" "用户说保留" "-" closed >/dev/null
"$here/log.sh" .dflow/demo.tsv decision "解析器先只做 v1" "a-2 报告" "-" ok >/dev/null
"$here/log.sh" .dflow/demo.tsv round "第 1 轮" "-" "-" ok >/dev/null
"$ln" line set demo a attempt=2 >/dev/null; echo "RECEIPT a 2 done $s2" > .dflow/demo/reports/a-2.md
out=$("$ln" status demo); rc=$?
[ $rc = 0 ] && [ "$(echo "$out" | wc -l | tr -d ' ')" = 3 ] && ok || bad "status summary: $rc $out"
echo "$out" | grep -q '^counts: 2 lines; .*dispatched 1.*receipts 2; passed 1$' && ok || bad "counts: $out"
echo "$out" | grep -qx 'changed: a b' && ok || bad "first status changed: $out"
echo "$out" | grep -qx 'gates open: 1' && ok || bad "gates: $out"
grep -q '接口用 v1 还是 v2' .dflow/demo/status.md && ! grep -q '要不要删旧表' .dflow/demo/status.md && ok || bad "gate list: $(cat .dflow/demo/status.md)"
grep -q "^| a | dispatched | headless | codex | 2 | 2026-10-24T00:00:00Z | done $s2 | pass @$s2 |" .dflow/demo/status.md && ok || bad "row a: $(cat .dflow/demo/status.md)"
grep -q '^- 解析器先只做 v1（a-2 报告；' .dflow/demo/status.md && ! grep -q '第 1 轮' .dflow/demo/status.md && ok || bad "decision rows: $(cat .dflow/demo/status.md)"
out=$("$ln" status demo); echo "$out" | grep -qx 'changed: none' && ok || bad "second status changed: $out"
"$ln" line set demo b state=blocked >/dev/null
out=$("$ln" status demo); echo "$out" | grep -qx 'changed: b' && ok || bad "changed after edit: $out"
# every shown field counts as a change: last progress, carrier, model
"$ln" line set demo a progress_at=2026-10-24T01:00:00Z >/dev/null
out=$("$ln" status demo); echo "$out" | grep -qx 'changed: a' && ok || bad "progress_at change not seen: $out"
"$ln" line set demo b carrier=headless model=claude >/dev/null
out=$("$ln" status demo); echo "$out" | grep -qx 'changed: b' && ok || bad "carrier/model change not seen: $out"
# verifier lines (v-<id>) get their own table
"$ln" line set demo v-a state=dispatched carrier=headless model=claude attempt=1 >/dev/null
"$ln" status demo >/dev/null
awk '/^## 验收线/ { f = 1 } f && /^\| v-a \|/ { found = 1 } END { exit !found }' .dflow/demo/status.md && [ "$(sed -n '/^## 验收线/q; /^| v-a |/p' .dflow/demo/status.md)" = "" ] && ok || bad "verifier table: $(cat .dflow/demo/status.md)"
# --print: the same board on stdout; nothing written, no snapshot, no lock taken
cp .dflow/demo/status.md "$t/st.md"; cp .dflow/demo/.status.snap "$t/st.snap"
"$ln" line set demo b state=dispatched >/dev/null
mkdir .dflow/demo/.lock   # a write lock held by someone else does not block a read
ls -la .dflow/demo > "$t/ls1"
out=$("$ln" status demo --print); rc=$?
[ $rc = 0 ] && echo "$out" | grep -q '^| b | dispatched |' && echo "$out" | grep -q '^## 等你定' && ok || bad "status --print: $rc $out"
cmp -s .dflow/demo/status.md "$t/st.md" && cmp -s .dflow/demo/.status.snap "$t/st.snap" && ls -la .dflow/demo | cmp -s - "$t/ls1" && ok || bad "status --print wrote something"
rmdir .dflow/demo/.lock
expect 2 "status with an unknown option" "$ln" status demo --write
# a 10-column table without init still renders (missing columns as "-")
printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\nz\t-\tx\tplanned\t-\t-\t-\t-\t0\t-\n' > .dflow/old.units.tsv
mkdir -p .dflow/old; printf 'id\tattempt\tsha\tresult\tevidence_type\tverifier\tevidence\tts\n' > .dflow/old/ledger.tsv
out=$("$ln" status old); [ $? = 0 ] && grep -q '^| z | planned | - | - | - | - | - | 未验 | - |' .dflow/old/status.md && ok || bad "old table status: $out $(cat .dflow/old/status.md)"
# R5: the verdict column is the effective verdict: a verifier's test fail, then a (permitted) self
# pass on the same sha, shows fail; the latest raw row is only in its own column, 原始最新
git checkout -qb we; echo e >> a.txt; git commit -qam "e try 1"; se=$(git rev-parse HEAD); git checkout -q -
"$ln" line set demo e state=dispatched attempt=1 paths=a.txt >/dev/null
printf 'dflow 线 demo/e/1\n验证     单命令验证：make check\n' > .dflow/demo/briefs/e-1.md
echo "RECEIPT e 1 done $se" > .dflow/demo/reports/e-1.md
"$ln" ledger record demo e 1 "$se" fail test codex "ci.log" >/dev/null
"$ln" ledger record demo e 1 "$se" pass self worker "single-command: make check" >/dev/null
out=$("$ln" status demo --print)
echo "$out" | grep -q "^| e | dispatched | - | - | 1 | - | done $se | fail @$se | pass self @${se:0:12} |" && ok || bad "board shows a self pass the verdict rejects: $(echo "$out" | grep '^| e ')"
echo "$out" | grep -q '| 验收 | 原始最新 |' && ok || bad "board header: $(echo "$out" | grep '^| 线')"

# concurrent writers keep every row (write lock + atomic replace)
rp=(); for i in 1 2 3 4 5 6 7 8; do "$ln" ledger record demo c 1 "$base" pass test w$i "e$i" >/dev/null & rp+=($!); done; wait "${rp[@]}"
[ "$(grep -c '^c	' .dflow/demo/ledger.tsv)" = 8 ] && ok || bad "concurrent records: $(grep -c '^c	' .dflow/demo/ledger.tsv) of 8"
[ ! -e .dflow/demo/.lock ] && ok || bad "write lock left behind"

# resource locks: machine-wide, so two working directories contend for the same one
mkdir -p "$t/wt1" "$t/wt2"
sleep 60 & pids+=($!); p1=$!; sleep 60 & pids+=($!); p2=$!
tok=$(cd "$t/wt1" && "$ln" lock acquire gui demo/a/1 "$p1" 2>/dev/null); [ $? = 0 ] && printf '%s' "$tok" | grep -Eqx '[0-9a-f]{32}' && ok || bad "acquire from wt1 printed no token: $tok"
out=$(cd "$t/wt2" && "$ln" lock acquire gui demo/b/1 "$p2" 2>&1); [ $? = 1 ] && echo "$out" | grep -q "held by demo/a/1" && ok || bad "second holder not refused: $out"
out=$(cd "$t/wt1" && "$ln" lock acquire gui demo/a/1 "$p1" 2>/dev/null); [ $? = 0 ] && [ "$out" = "$tok" ] && ok || bad "re-acquire by the holder: $out"
out=$("$ln" lock show gui); echo "$out" | grep -qx "attempt: demo/a/1" && echo "$out" | grep -qx "pid: $p1" && echo "$out" | grep -q "^command: sleep 60" && echo "$out" | grep -qx "state: alive" && ! echo "$out" | grep -q "$tok" && ok || bad "show: $out"
# the same attempt name from another repository (or its string as a token) does not release it
expect 1 "release by attempt name" "$ln" lock release gui demo/a/1
expect 1 "release with another token" "$ln" lock release gui 0123456789abcdef0123456789abcdef
[ -d "$DFLOW_LOCK_DIR/gui" ] && ok || bad "lock gone after refused releases"
# the standard brief line keeps the resource command's exit code and releases the lock
out=$(sh -c 'tok=$("$0" lock acquire gui2 demo/a/1 "$1") || exit 1; false; rc=$?; "$0" lock release gui2 "$tok" >/dev/null; exit $rc' "$ln" "$p1" 2>/dev/null); rc=$?
[ $rc = 1 ] && [ ! -d "$DFLOW_LOCK_DIR/gui2" ] && ok || bad "brief pattern: rc $rc, lock $(ls "$DFLOW_LOCK_DIR")"
out=$(sh -c 'tok=$("$0" lock acquire gui demo/b/1 "$1") || exit 7; echo used; rc=$?; "$0" lock release gui "$tok"; exit $rc' "$ln" "$p2" 2>/dev/null); rc=$?
[ $rc = 7 ] && ! echo "$out" | grep -q used && [ -d "$DFLOW_LOCK_DIR/gui" ] && ok || bad "brief pattern when refused: rc $rc $out"
expect 0 "release by the holder's token" "$ln" lock release gui "$tok"
expect 0 "show free" "$ln" lock show gui; [ "$out" = "free gui" ] && ok || bad "show after release: $out"
expect 1 "acquire for a pid that is not running" "$ln" lock acquire gui demo/a/1 999999
# held by a process that is gone (stop confirmed): another attempt takes it over
sh -c 'exit 0' & dead=$!; wait "$dead"
mkdir -p "$DFLOW_LOCK_DIR/gui"; printf 'attempt: demo/a/1\npid: %s\ncommand: sleep 60\nsince: 2026-10-24T00:00:00Z\n' "$dead" > "$DFLOW_LOCK_DIR/gui/holder"
out=$("$ln" lock acquire gui demo/b/1 "$p2" 2>&1); [ $? = 0 ] && echo "$out" | grep -q "took over" && ok || bad "takeover of a gone holder: $out"
# a live pid that now runs another command (pid reused) is gone as a holder
printf 'attempt: demo/a/1\npid: %s\ncommand: some-old-command\nsince: 2026-10-24T00:00:00Z\n' "$p1" > "$DFLOW_LOCK_DIR/gui/holder"
out=$("$ln" lock acquire gui demo/b/1 "$p2" 2>&1); [ $? = 0 ] && ok || bad "takeover of a reused pid: $out"
# stop not confirmed: the holder still runs, so its lock is not reused
printf 'attempt: demo/a/1\npid: %s\ncommand: %s\nsince: 2026-10-24T00:00:00Z\n' "$p1" "$(ps -ww -o command= -p "$p1")" > "$DFLOW_LOCK_DIR/gui/holder"
expect 1 "unconfirmed stop keeps the lock" "$ln" lock acquire gui demo/a/2 "$p2"
# a live holder whose command ps cannot read (no ps) is not judged gone
mkdir -p "$t/nops"; printf '#!/bin/sh\necho "ps: operation not permitted" >&2; exit 1\n' > "$t/nops/ps"; chmod +x "$t/nops/ps"
printf 'attempt: demo/a/1\npid: %s\ncommand: some-old-command\nsince: 2026-10-24T00:00:00Z\ntoken: x\n' "$p1" > "$DFLOW_LOCK_DIR/gui/holder"
out=$(PATH="$t/nops:$PATH" "$ln" lock acquire gui demo/a/2 "$p2" 2>&1); [ $? = 1 ] && grep -qx "token: x" "$DFLOW_LOCK_DIR/gui/holder" && ok || bad "no ps: lock taken over: $out"
# concurrent takeovers of one stale lock: exactly one winner, the holder names it, nothing left behind
printf 'attempt: demo/a/1\npid: %s\ncommand: sleep 60\nsince: 2026-10-24T00:00:00Z\n' "$dead" > "$DFLOW_LOCK_DIR/gui/holder"
: > "$t/won"; rp=()
for i in 1 2 3 4 5 6 7 8; do (cd "$t/wt$(( i % 2 + 1 ))" && "$ln" lock acquire gui "demo/t$i/1" "$p2" >/dev/null 2>&1 && echo "demo/t$i/1" >> "$t/won") & rp+=($!); done; wait "${rp[@]}"
[ "$(wc -l < "$t/won" | tr -d ' ')" = 1 ] && grep -qx "attempt: $(cat "$t/won")" "$DFLOW_LOCK_DIR/gui/holder" && ok || bad "concurrent takeovers: winners $(tr '\n' ' ' < "$t/won"); holder $(cat "$DFLOW_LOCK_DIR/gui/holder")"
[ -z "$(ls -d "$DFLOW_LOCK_DIR"/gui.* 2>/dev/null | cat)" ] && ok || bad "takeover left $(ls -d "$DFLOW_LOCK_DIR"/gui.*)"
kill "$p1" "$p2" 2>/dev/null
# R2: acquire, takeover and release are one transaction each. A release is paused (by a python3
# stand-in around its rename) before and after it moves the lock aside; meanwhile its holder dies, a
# second attempt tries to take the stale lock over, and a third tries to acquire while the lock
# directory is away. Neither may get the lock inside that window (they wait or are refused), and in
# the end exactly one holds it, the holder file names it, and no moved-aside directory is left.
realpy=$(command -v python3); pz="$t/pause"; mkdir -p "$t/slowpy" "$pz"
cat > "$t/slowpy/python3" <<'W'
#!/bin/sh
case "${5:-}" in *.rel.*)
    touch "$PAUSE/pre"; while [ ! -e "$PAUSE/go1" ]; do sleep 0.05; done
    "$REALPY" "$@"; rc=$?
    touch "$PAUSE/post"; while [ ! -e "$PAUSE/go2" ]; do sleep 0.05; done
    exit $rc ;;
esac
exec "$REALPY" "$@"
W
chmod +x "$t/slowpy/python3"
waitfor() { local i; for i in $(seq 1 100); do [ -e "$1" ] && return 0; sleep 0.1; done; return 1; }
sleep 60 & pids+=($!); pa=$!; sleep 60 & pids+=($!); pb=$!; sleep 60 & pids+=($!); pc=$!
ta=$("$ln" lock acquire gui3 demo/a/1 "$pa" 2>/dev/null) || bad "test setup: acquire gui3"
( PAUSE=$pz REALPY=$realpy PATH="$t/slowpy:$PATH" "$ln" lock release gui3 "$ta" > "$t/rel.out" 2>&1 ) & rel=$!
waitfor "$pz/pre" || bad "test setup: the release never reached its move"
kill "$pa"; wait "$pa" 2>/dev/null
( DFLOW_LOCK_TXN_WAIT=30 "$ln" lock acquire gui3 demo/b/1 "$pb" > "$t/b.tok" 2> "$t/b.err"; echo $? > "$t/b.rc" ) & bp=$!
sleep 1.5; touch "$pz/go1"; waitfor "$pz/post" || bad "test setup: the release never finished its move"
( DFLOW_LOCK_TXN_WAIT=30 "$ln" lock acquire gui3 demo/c/1 "$pc" > "$t/c.tok" 2> "$t/c.err"; echo $? > "$t/c.rc" ) & cq=$!
sleep 1.5
inwin=""; for w in b c; do [ "$(cat "$t/$w.rc" 2>/dev/null)" = 0 ] && inwin="$inwin $w"; done
[ -z "$inwin" ] && ok || bad "acquired while a release had the lock moved aside:$inwin ($(cat "$t/b.err" "$t/c.err"))"
touch "$pz/go2"; wait "$rel" "$bp" "$cq"
won=""; for w in b c; do [ "$(cat "$t/$w.rc")" = 0 ] && won="$won $w"; done
[ "$won" = " b" ] || [ "$won" = " c" ] && grep -qx "attempt: demo/${won# }/1" "$DFLOW_LOCK_DIR/gui3/holder" && grep -qx "token: $(cat "$t/${won# }.tok")" "$DFLOW_LOCK_DIR/gui3/holder" && ok || bad "after the release: winners$won; holder $(cat "$DFLOW_LOCK_DIR/gui3/holder" 2>&1); release $(cat "$t/rel.out")"
[ -z "$(ls -d "$DFLOW_LOCK_DIR"/gui3.* 2>/dev/null | cat)" ] && ok || bad "a moved-aside lock was left: $(ls -d "$DFLOW_LOCK_DIR"/gui3.*)"
grep -q "^ok released" "$t/rel.out" && ok || bad "the paused release: $(cat "$t/rel.out")"
# a transaction whose holder died does not block: the kernel drops the flock with its process
mkdir -p "$DFLOW_LOCK_DIR/.txn"
python3 -I -c 'import fcntl, os, sys; fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND); fcntl.flock(fd, fcntl.LOCK_EX); os._exit(0)' "$DFLOW_LOCK_DIR/.txn/gui4"
out=$(DFLOW_LOCK_TXN_WAIT=2 "$ln" lock acquire gui4 demo/b/1 "$pb" 2>&1); [ $? = 0 ] && ok || bad "a dead transaction holder blocked the lock: $out"
# while a live process holds the transaction, an acquire waits and is then refused, touching nothing
python3 -I -c 'import fcntl, os, sys, time; fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND); fcntl.flock(fd, fcntl.LOCK_EX); time.sleep(30)' "$DFLOW_LOCK_DIR/.txn/gui5" & pids+=($!); sleep 0.5
out=$(DFLOW_LOCK_TXN_WAIT=1 "$ln" lock acquire gui5 demo/b/1 "$pb" 2>&1); [ $? = 1 ] && echo "$out" | grep -q busy && [ ! -e "$DFLOW_LOCK_DIR/gui5" ] && ok || bad "busy transaction: $out"
# a resource named like another's transaction file never collides with it, in either order
for r in "gui6 gui6.txn" "gui7.txn gui7"; do set -- $r
    t1=$("$ln" lock acquire "$1" demo/b/1 "$pb" 2>/dev/null) && "$ln" lock release "$1" "$t1" >/dev/null &&
    t2=$("$ln" lock acquire "$2" demo/b/1 "$pb" 2>/dev/null) && "$ln" lock release "$2" "$t2" >/dev/null &&
    t3=$("$ln" lock acquire "$1" demo/b/1 "$pb" 2>/dev/null) && "$ln" lock release "$1" "$t3" >/dev/null && ok || bad "resources $1 and $2 collide"
done
kill "$pb" "$pc" 2>/dev/null

expect 2 "usage" "$ln"
expect 1 "bad slug" "$ln" status "../x"
expect 1 "bad resource" "$ln" lock show "../x"
echo "lines-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
