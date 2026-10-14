#!/usr/bin/env bash
# Tests for timeline.py: merge two sessions by time, results paired, DANGER marking, missing session.
set -u
here=$(cd "$(dirname "$0")" && pwd); pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
export DFLOW_TRANSCRIPTS="$here/timeline-cases"
out=$(python3 -I "$here/timeline.py" aaaa1111 bbbb2222); rc=$?
[ $rc = 0 ] && ok || bad "exit $rc"
[ "$(echo "$out" | wc -l | tr -d ' ')" = 4 ] && ok || bad "row count: $out"
[ "$(echo "$out" | cut -f2 | tr '\n' ' ')" = "aaaa1111 bbbb2222 bbbb2222 aaaa1111 " ] && ok || bad "not merged by time: $out"
echo "$out" | grep -q $'git push origin HEAD\tDANGER error' && ok || bad "push not marked DANGER"
echo "$out" | grep -q $'git log --oneline -3\tok' && ok || bad "git log wrongly marked"
echo "$out" | grep -q $'src/a.py\tok\tedited' && ok || bad "list result not flattened"
err=$(python3 -I "$here/timeline.py" aaaa1111 cccc3333 2>&1 >/dev/null); rc=$?
[ $rc = 2 ] && ok || bad "missing session exit $rc"
echo "$err" | grep -q $'未核实\tcccc3333' && ok || bad "missing not reported"
f="$here/timeline-cases/proj/aaaa1111.jsonl"
python3 -I "$here/timeline.py" "$f" | grep -q 'unittest' && ok || bad "path argument"
d=$(python3 -I "$here/timeline.py" --danger aaaa1111 bbbb2222); rc=$?
[ $rc = 1 ] && [ "$(echo "$d" | wc -l | tr -d ' ')" = 1 ] && ok || bad "--danger: exit $rc: $d"
python3 -I "$here/timeline.py" --danger bbbb2222 >/dev/null; [ $? = 0 ] && ok || bad "--danger clean exit"
echo "timeline-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
