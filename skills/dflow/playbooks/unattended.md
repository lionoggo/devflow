### 无人值守 (unattended)

**You own the exit condition. Frame it once, then drive to it without the
user; stop only at done, the deadline, or a real dead end.** From pstack
`autonomous-run`, `pause-safely`, `session-pickup`, `show-me-your-work`, and
Orchestrate's gates. Principles: 不停下等人, 小步可验证, 真实证据, 对齐目标.

`$S` below is this skill's directory. Run files live in `<repo>/.dflow/` and
are never committed: `<slug>.md` (manifest), `<slug>.lock/` (lease),
`<slug>.tsv` (log). The slug matches `[a-z0-9][a-z0-9-]{0,62}`. In Codex,
the loop, waits, and notifications follow `references/hosts.md`.

Which part to run: "继续无人值守 <slug>" is **Pickup** when this session does
not hold the lease, and **Round** when it does (that is how a `/loop` wake,
or a goal continuation in Codex, reaches you). "暂停", "先停一下", "我要重启" is **Pause**. "去睡了", "别停" never
pause. Anything else starts at **Frame**.

## Frame (the one stop)

One screen, then wait for "开始". Check every fact first; never ask what you
can run.

1. **Done conditions**: each a command, its expected result, and its baseline
   output now. Ordered stages S1..Sn are fine; with an approved plan, take its
   stages and acceptance. A duration alone ("跑 4 小时") is not a condition:
   add a checkable one. If a cheaper implementation that defeats the intent
   would also pass, add a condition that tells them apart. Say what counts as
   progress: by default "one unit's check passes and no finished condition
   regresses"; for a count or timing condition, name the metric. Read each
   baseline against its expected result: anything it shows that the planned
   work will not change (a test that always skips, a failure from the
   environment) means the wording is wrong; fix it here, not after "开始".
2. **Units**: from the plan or the goal, riskiest first, with dependencies and
   which are independent.
3. **Branch**: on a clean tree, `dflow/<slug>` from HEAD. A dirty tree: list
   the files and stop; never clean or stash.
4. **Paths**: allowed to write (globs), and protected (every test, sample,
   and script the conditions use). A needed edit outside them is a gate.
   A protected test whose asserted facts the plan must change (a table
   list, a snapshot, a route count) goes to step 6 now, not to a gate at
   night. Check that each condition command skips `.dflow/` (scratch files
   live there, and tools that read only `.gitignore` will lint or test
   them); if not, the ignore goes into the tool's config as the first
   commit when that file is in `allow`, otherwise into step 6.
5. **Will not do**: push, merge, rebase, reset, stash, clean, cherry-pick,
   amend; switch or delete branches, tags, worktrees; edit protected paths;
   write to outside systems. The one exception: in a parallel run,
   `parallel.sh land` and `cleanup` may cherry-pick, remove worktrees, and
   delete the branches it created. The run sends two kinds of device notifications
   (see **Notify**); "开始" approves that.
6. **Known open questions**: product or preference calls visible now, each
   with its default, so the user can change it here.
7. **Deadline**: default 8 hours from start, as an absolute UTC time. A pickup
   never restarts it.
8. **Environment**: needs a mode that never stops for a permission prompt
   (`references/hosts.md`);
   `caffeinate` keeps the Mac awake; do not edit this repo by hand while it
   runs (say "暂停" first). First unattended run of this kind: suggest the
   user watch the first two rounds.
9. **Parallel or in order**: run the throughput check in
   `references/parallel.md`. Show both plans with their estimated cost and
   wall time; the default is in order. "开始，并行" picks parallel and
   approves the worktrees `parallel.sh` creates and removes.
10. **Start line**: check that the Skill tool can call `loop`. If it cannot,
   tell the user to reply with `/loop /dflow 继续无人值守 <slug>` instead of
   "开始", and do steps 1–5 below when that arrives. In Codex the start line
   is "开始", but the session must be interactive (app, IDE, or TUI): in
   `codex exec` say the loop cannot run there and stop.

On "开始":
1. Re-check HEAD, the tree, and each baseline output. Anything changed since
   the frame: stop and show what changed.
2. Create the branch. Make sure the exclude file
   (`git rev-parse --git-path info/exclude`) has `.dflow/`; for a parallel
   run, `parallel.sh prepare <slug>` also adds `.claude/worktrees/`.
3. Write `.dflow/<slug>.md`: first a block of `key: value` lines (`slug`,
   `branch`, `base` full SHA, `deadline`, `allow` and `protect` as
   space-separated globs), a blank line, then the human part: goal, stages and
   conditions with expected results and the progress rule, units, open
   questions with defaults. A check script the frame adds (an anti-shortcut
   smoke test) lives beside it as `.dflow/<slug>-<name>`; it is protected. Never edit it afterwards unless the user says so;
   then re-claim and log a `correction` row.
4. `$S/scripts/run-state.sh claim <slug>`, then `run-state.sh caffeinate <slug>`.
5. Log `start` (`$S/scripts/log.sh .dflow/<slug>.tsv start …`): evidence holds
   the base SHA, a hash of `git ls-remote` (or the local remote's
   `show-ref`), the SHA-256 of each `.dflow/<slug>-<name>` check script (Git
   does not see them), and the full session id.
6. Start the loop: Skill `loop` with args `/dflow 继续无人值守 <slug>`, no
   interval (dynamic). In Codex: `create_goal` with the objective
   `dflow 无人值守 <slug>：每次继续都是 <this file's absolute path> 的一个 Round，只经 Close 或 Pause 结束`
   and no token budget. Then run the first round now.

## Round

Every wake-up is a Round: a `/loop` wake or goal continuation, or a parallel
worker's completion notification. In a parallel run, a Round handles arrived
completions per `references/parallel.md`; while workers are still running, a
`/loop` wake dispatches nothing new. In Codex, workers do not wake you: a
Round with workers running ends in `wait_agent` on them.

1. `$S/scripts/run-state.sh check <slug>`:
   - exit 0: go on;
   - exit 3 (`UNLOGGED <sha>` lines): commits no row names. Rerun the
     checks; pass, log one row naming each as `commit <sha>`; fail,
     `git revert --no-edit` them newest first and log a no-progress round;
   - exit 4: deadline passed, go to **Close**;
   - exit 1 with "lease held by" another session: stop your loop (Codex:
     `update_goal` `blocked`), write nothing;
   - any other exit 1: log a `blocked` row with the output, notify, stop the
     loop, and reply. Uncommitted files of unknown origin are never reverted
     or deleted.
2. Read the manifest and the last 15 log rows. Trust files, not memory.
3. Pick the riskiest open unit that is not done, gated, or dead; take its
   smallest next step; state the assumption.
4. Change it. Run the step's check plus every condition of every finished
   stage and of the current stage.
5. End the round clean:
   - Progress by the manifest's rule, nothing regressed: `git add` only the
     paths you edited this round, commit, log `round` with `commit <sha>`.
   - Otherwise: restore only the paths you edited this round and delete only
     files you created this round; log `round` with why and the next idea. A
     path in `git status` you did not touch: leave it, log `blocked`, notify,
     stop.
6. Side findings: a tool failure or related bug inside `allow` gets its own
   commit and a `side` row; trouble inside a protected path (a flaky check)
   is not fixed, the unit is gated; anything outside scope goes to the
   closeout's follow-ups.
7. Long waits (builds, benchmarks): background Bash or Monitor to wake you,
   one waiter at a time, never sleep-polling. Codex: run it in the foreground
   with a long `timeout_ms`, or hand it to a worker and `wait_agent`.
8. Dead end per unit: two independent approaches each with concrete failure
   evidence, and at least 30 minutes of work on it (the manifest may change
   the floor; waiting time does not count). Log `dead`, move to another unit.
9. A stage's conditions all pass: log `stage-done`, go to the next stage. A
   stuck stage does not block later stages that do not depend on it.
10. Before starting a new step, check the deadline; past it, do not start
    one. A step already verified commits as usual.
11. Go to **Close** when every condition passes, the deadline has passed, or
    every remaining unit is done, dead, or gated with nothing independent
    left. A plateau is not a stop: pivot. Never relax or reinterpret a
    condition. One that turns out wrong (no correct implementation can pass
    it): log a `gate` with the corrected wording as its default and keep
    reporting the original; never edit the manifest's conditions yourself.

**Gates** (a product or preference call no experiment settles, or a unit that
needs a "will not do" action): log `gate` with question, options, default,
reason, and how to change it; notify. Work on independent units first. Only
when none are left, go ahead on the default: those commits start with
`default:`, and at most one more unit is built on a default before the rest of
its dependents are gated. A unit whose code would stay the same whichever
option is picked (it only calls or combines the defaulted units) does not
depend on the gate; do it normally. A unit that needs a forbidden action is never done
on a default.

**Log** per `references/decision-log.md`, with phases `start round gate
default dead stage-done side blocked pause close correction`; at least one
row per round.

**Notify** with PushNotification (Codex: `$S/scripts/notify.sh`) only when a `gate` row is written ("需要你
定：<问题>，已先做别的 / 已按默认 <值> 处理") and when the run stops
("<slug> 完成 / 部分完成 / 受阻"). A failed send is not retried; mention it
in the closeout.

## Pause (only when the user says so)

Finish the current step and commit it, or restore it. Only when it can neither
finish nor be restored without losing useful work, commit your own edits as
one `wip:` commit (the one exception to committing only checked units). Log
`pause` with the current unit, the next step, and the traps. Stop the loop
(Codex: `update_goal` `paused`), `run-state.sh release <slug>`. Reply: where it stands, commits, whether the
tree is clean, and the first step on resume.

## Pickup (a new session)

1. `run-state.sh claim <slug>`. Refused because another agent process
   (claude or codex) is alive: tell the user to close that session first; stop.
2. `run-state.sh check <slug>` and handle it as in **Round** step 1.
3. Read the manifest; rerun every condition yourself, never trusting a logged
   pass.
4. Log `start` naming the inherited ts range and your full session id. Keep
   the manifest's deadline.
5. A run that paused on a `wip:` commit: verify it or revert it first. A
   parallel run: handle each `dispatched` unit per the Pickup section of
   `references/parallel.md`.
6. Do not redo committed units; find the next step from the log and
   `git log`.
7. `run-state.sh caffeinate <slug>`, start the loop as in **Frame** step 6,
   and run a round.

## Close

1. Uncommitted changes outside `.dflow/`: report them, do not clean.
2. Commit first, then rerun every condition on that HEAD; keep the real
   output and name the SHA. A pass on an uncommitted tree is not a pass on
   a commit.
3. Timeline: `python3 -I $S/scripts/timeline.py --say <every session id in the
   log's start rows>` into a directory from `$S/scripts/scratch.sh close`. A missing
   transcript is listed as 未核实.
4. Cross-check: each progress row matches a real commit in
   `git log <base>..HEAD`; each check the log claims appears in the timeline.
   For each acceptance item, read one test that carries it against
   `principles/test-behavior.md`; one that would pass with the feature
   removed does not count for that item, so report it as 未证实.
   Append `correction` rows for mismatches.
5. Detection, instead of a guard: `run-state.sh scope <slug>` (protected or
   outside-scope files changed); each `.dflow/<slug>-<name>` check script
   against its SHA-256 in the first `start` row; `timeline.py --danger <ids>`
   (forbidden git commands, whole multi-line commands scanned; exit 1 when
   any); remote refs
   against the `start` hash, reported as "未观察到变化" or "有变化" (this
   cannot prove nothing was pushed). Report findings; never roll back on your
   own.
6. Cross-model review of HEAD; record that SHA as the review head. Give
   `codex exec -s read-only` the manifest, the log,
   `git log -p <base>..HEAD`, the timeline file, and the plan and requirement
   docs the manifest names; ask for decisions with thin evidence, checks
   claimed without a run (in the log or in what the agent said), approvals the
   main session credits to the user with no matching user line, choices risky
   in hindsight, what a quick read would miss, and the two requirement
   questions in `SKILL.md` **Cross-model review**. Pass the user's
   constraints on verbatim. Unavailable: "未审查：<原因>"; go to step 9.
7. Fix once: check each finding against the code; fix the ones that hold and
   need no new authority in one batch, with the failure path the finding
   names checked, not only the old tests. Skip the batch when the deadline
   leaves no time for its checks and step 8. Log each fix as `side`, then
   redo steps 2, 4, and 5.
8. Review the fix once: if anything was committed after the review head,
   give `codex exec -s read-only` the first review, `git log -p <review
   head>..HEAD`, and the current code around each touched path; ask whether
   each fix resolves the whole finding, what related paths it missed, and
   whether the log or docs now claim more than the code does. After this,
   commit nothing more, not even wording; what it finds goes to the user.
   Unavailable: the range `<review head>..HEAD` is 未审查.
9. Log `close`; the decision column is exactly 完成, 部分完成, or 受阻,
   judged by the conditions, not by a clean review.
10. Stop the loop (Codex: `update_goal` `complete`, or `blocked` when 受阻),
   `run-state.sh release <slug>` (stops this run's caffeinate only), notify.

**Reply:**

```text
**结果**：<完成 / 部分完成 / 受阻>。<一句话>
- 完成条件：<每条 → 最终真实输出>
- 提交：<基线..HEAD，n 个；按默认做的单独列出>
- 按默认做的决定：<问题 → 默认值 → 怎么改（git revert <sha>）>
- 卡住和死路：<单元 → 原因 → 需要你做什么>
- 收尾检测：受保护路径 <未改 / 改了哪些>；范围外文件 <无 / 哪些>；危险命令 <无 / 有哪些>；远端 <未观察到变化 / 有变化>
- 后续事项：<范围外发现；没有就省略>
- 影响面：<见 SKILL.md>
- 日志：.dflow/<slug>.tsv（清单 .dflow/<slug>.md）
**需要你注意**
审查：codex（没审就写"未审查：<原因>"）
- <审查要点，最多 5 条，每条指向日志的某一行或某个时刻；没修或只修了一半的意见优先，两轮审查都算；审后改动没补审就写"未审查：<审查时 HEAD>..HEAD，<原因>">
```
