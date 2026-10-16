#!/usr/bin/env bash
# Tests for timeline.py: merge two sessions by time, results paired, DANGER marking, missing session, --say.
set -u
here=$(cd "$(dirname "$0")" && pwd); pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
export DFLOW_TRANSCRIPTS="$here/timeline-cases"
out=$(python3 -I "$here/timeline.py" aaaa1111 bbbb2222); rc=$?
[ $rc = 0 ] && ok || bad "exit $rc"
[ "$(echo "$out" | wc -l | tr -d ' ')" = 9 ] && ok || bad "row count: $out"
[ "$(echo "$out" | cut -f2 | tr '\n' ' ')" = "bbbb2222 aaaa1111 bbbb2222 bbbb2222 aaaa1111 bbbb2222 agent-w1 bbbb2222 bbbb2222 " ] && ok || bad "not merged by time: $(echo "$out" | cut -f2 | tr '\n' ' ')"
echo "$out" | grep -q $'agent-w1\tBash\tgit stash\tDANGER ok' && ok || bad "subagent danger not caught"
echo "$out" | grep -q $'parallel.sh land demo u1 && git add app\tok' && ok || bad "sanctioned land flagged"
echo "$out" | grep -q $'parallel.sh land demo u1 && git push origin HEAD\tDANGER ok' && ok || bad "push after land not caught"
echo "$out" | grep -q $'git commit -qm x ⏎ git push origin HEAD\tDANGER ok' && ok || bad "push on a later line not caught: $out"
echo "$out" | grep -q $'git switch -c dflow/demo\tok' && ok || bad "run branch creation flagged"
echo "$out" | grep -q $'git push origin HEAD\tDANGER error' && ok || bad "push not marked DANGER"
echo "$out" | grep -q $'git log --oneline -3\tok' && ok || bad "git log wrongly marked"
echo "$out" | grep -q $'src/a.py\tok\tedited' && ok || bad "list result not flattened"
err=$(python3 -I "$here/timeline.py" aaaa1111 cccc3333 2>&1 >/dev/null); rc=$?
[ $rc = 2 ] && ok || bad "missing session exit $rc"
echo "$err" | grep -q $'未核实\tcccc3333' && ok || bad "missing not reported"
f="$here/timeline-cases/proj/aaaa1111.jsonl"
python3 -I "$here/timeline.py" "$f" | grep -q 'unittest' && ok || bad "path argument"
d=$(python3 -I "$here/timeline.py" --danger aaaa1111 bbbb2222); rc=$?
[ $rc = 1 ] && [ "$(echo "$d" | wc -l | tr -d ' ')" = 4 ] && ok || bad "--danger: exit $rc: $d"
python3 -I "$here/timeline.py" --danger aaaa1111 >/dev/null; [ $? = 1 ] && ok || bad "--danger exit"
s=$(python3 -I "$here/timeline.py" --say aaaa1111); rc=$?
echo "$s" | cut -f1 | grep -qx '' && bad "row without a timestamp (copied request entry)" || ok
[ $rc = 0 ] && ok || bad "--say exit $rc"
echo "$s" | grep -q $'\tassistant\t测试都跑过了。 ⏎ 下一步 git push origin HEAD 被拒\t-\t' && ok || bad "--say assistant text: $s"
echo "$s" | grep -q $'\tuser\t允许改 migrate 测试\t-' && ok || bad "--say user string"
echo "$s" | grep -q $'\tuser\t继续\t-' && ok || bad "--say user text blocks"
echo "$s" | grep -q $'unittest\tok\tOK ⏎ Ran 2 tests' && ok || bad "--say long result"
echo "$s" | grep -q 'injected' && bad "--say kept a meta message" || ok
echo "$s" | grep -q $'\tassistant\t.*DANGER' && bad "--say text marked DANGER" || ok
echo "$s" | grep -q $'agent-w1\tprompt\t实施单元 u1\t-' && ok || bad "--say subagent prompt"
echo "$s" | grep -q $'\tnotice\t<task-notification>' && ok || bad "--say task notice"
[ "$(echo "$s" | grep -c $'\t\(Bash\|Edit\)\t')" = 3 ] && ok || bad "--say lost tool rows: $s"
for c in 'git switch -C "$(git branch --show-current)" abc123:False' "git switch -C unit-u1 abc:True" "git switch -C worktree-agent-abc 1234:False" "git switch main:True" "git switch -C other HEAD:True" "git merge-base HEAD main:False" "git merge dflow/x:True"; do
    r=$(python3 -I -c "import sys,re;sys.path.insert(0,'$here');import timeline;print(bool(timeline.DANGER.search(sys.argv[1])))" "${c%:*}")
    [ "$r" = "${c##*:}" ] && ok || bad "danger($c) = $r"
done
rm -rf "$here/__pycache__"
echo "timeline-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
