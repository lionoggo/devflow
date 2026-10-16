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
python3 -I "$here/timeline.py" --say dddd4444 | grep -q 'pnpm lint && echo checked' && ok || bad "--say cut a long command"
python3 -I "$here/timeline.py" dddd4444 | grep -q '…\[截断，原文 [0-9]* 字\]' && ok || bad "default mode does not mark a cut command"
echo "$s" | grep -q 'injected' && bad "--say kept a meta message" || ok
echo "$s" | grep -q $'\tassistant\t.*DANGER' && bad "--say text marked DANGER" || ok
echo "$s" | grep -q $'agent-w1\tprompt\t实施单元 u1\t-' && ok || bad "--say subagent prompt"
echo "$s" | grep -q $'\tnotice\t<task-notification>' && ok || bad "--say task notice"
[ "$(echo "$s" | grep -c $'\t\(Bash\|Edit\)\t')" = 3 ] && ok || bad "--say lost tool rows: $s"
for c in 'git switch -C "$(git branch --show-current)" abc123:False' "git switch -C unit-u1 abc:True" "git switch -C worktree-agent-abc 1234:False" "git switch main:True" "git switch -C other HEAD:True" "git merge-base HEAD main:False" "git merge dflow/x:True"; do
    r=$(python3 -I -c "import sys,re;sys.path.insert(0,'$here');import timeline;print(bool(timeline.DANGER.search(sys.argv[1])))" "${c%:*}")
    [ "$r" = "${c##*:}" ] && ok || bad "danger($c) = $r"
done
# Codex rollouts: thread id lookup, subagents by parent_thread_id, copied history skipped
export DFLOW_CODEX_SESSIONS="$here/timeline-cases/codex"
P=cccc0001-0000-7000-8000-000000000001
c=$(python3 -I "$here/timeline.py" "$P"); rc=$?
[ $rc = 0 ] && ok || bad "codex exit $rc"
[ "$(echo "$c" | wc -l | tr -d ' ')" = 6 ] && ok || bad "codex row count: $c"
echo "$c" | grep -q $'cccc0001\tBash\tgit status --short\tok\tM a.py' && ok || bad "codex exec_command row: $c"
echo "$c" | grep -q $'cccc0001\tapply_patch\t/r/a.py /r/b.py\tok' && ok || bad "codex apply_patch row"
echo "$c" | grep -q $'agent-cccc0002\tBash\tgit stash\tDANGER ok' && ok || bad "codex subagent danger"
echo "$c" | grep -q $'git commit -qm x ⏎ git push origin HEAD\tDANGER error' && ok || bad "codex exit code 1 not error, or push missed"
echo "$c" | grep -q 'git push origin main' && bad "codex: forked subagent's copied history counted" || ok
echo "$c" | grep -q 'cccc0003' && bad "codex: unrelated thread pulled in" || ok
cs=$(python3 -I "$here/timeline.py" --say "$P")
echo "$cs" | grep -q $'\tuser\t开始\t-' && ok || bad "codex --say user"
[ "$(echo "$cs" | grep -c $'\tuser\t')" = 1 ] && ok || bad "codex --say kept injected context: $cs"
echo "$cs" | grep -q $'\tassistant\t改好了，测试通过。 ⏎ 下一步提交' && ok || bad "codex --say assistant"
echo "$cs" | grep -q $'agent-cccc0002\tprompt\t实施单元 u1' && ok || bad "codex --say subagent prompt"
echo "$cs" | grep -q $'\tnotice\tturn started by goal' && ok || bad "codex --say goal turn"
echo "$cs" | grep -q $'\tnotice\t<subagent_notification>' && ok || bad "codex --say subagent notice"
echo "$cs" | grep -q $'\tnotice\t<codex_internal_context source="goal">' && ok || bad "codex --say goal context not a notice"
python3 -I "$here/timeline.py" --danger "$P" >/dev/null; [ $? = 1 ] && ok || bad "codex --danger exit"
f=$(ls "$here"/timeline-cases/codex/2026/10/16/rollout-*-"$P".jsonl)
[ "$(python3 -I "$here/timeline.py" "$f" | wc -l | tr -d ' ')" = 5 ] && ok || bad "codex path argument (parent only)"
rm -rf "$here/__pycache__"
echo "timeline-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
