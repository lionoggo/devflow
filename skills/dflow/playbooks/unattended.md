### 无人值守 (unattended)

**You own the exit condition. Frame it once, then drive to it without the
user; stop only at done, the deadline, or a real dead end.** From pstack
`autonomous-run`, `pause-safely`, `session-pickup`, `show-me-your-work`, and
Orchestrate's gates. Principles: 不停下等人, 小步可验证, 真实证据, 对齐目标.

`$S` below is this skill's directory. Run files live in `<repo>/.dflow/` and
are never committed: `<slug>.md` (manifest), `<slug>.lock/` (lease),
`<slug>.tsv` (log). The slug matches `[a-z0-9][a-z0-9-]{0,62}`.

Which part to run: "继续无人值守 <slug>" is **Pickup** when this session does
not hold the lease, and **Round** when it does (that is how `/loop` wakes
you). "暂停", "先停一下", "我要重启" is **Pause**. "去睡了", "别停" never
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
   regresses"; for a count or timing condition, name the metric.
2. **Units**: from the plan or the goal, riskiest first, with dependencies and
   which are independent.
3. **Branch**: on a clean tree, `dflow/<slug>` from HEAD. A dirty tree: list
   the files and stop; never clean or stash.
4. **Paths**: allowed to write (globs), and protected (every test, sample,
   and script the conditions use). A needed edit outside them is a gate.
5. **Will not do**: push, merge, rebase, reset, stash, clean, cherry-pick,
   amend; switch or delete branches, tags, worktrees; edit protected paths;
   write to outside systems. The run sends two kinds of device notifications
   (see **Notify**); "开始" approves that.
6. **Known open questions**: product or preference calls visible now, each
   with its default, so the user can change it here.
7. **Deadline**: default 8 hours from start, as an absolute UTC time. A pickup
   never restarts it.
8. **Environment**: needs a mode that never stops for a permission prompt;
   `caffeinate` keeps the Mac awake; do not edit this repo by hand while it
   runs (say "暂停" first). First unattended run of this kind: suggest the
   user watch the first two rounds.
9. **Start line**: check that the Skill tool can call `loop`. If it cannot,
   tell the user to reply with `/loop /dflow 继续无人值守 <slug>` instead of
   "开始", and do steps 1–5 below when that arrives.

On "开始":
1. Re-check HEAD, the tree, and each baseline output. Anything changed since
   the frame: stop and show what changed.
2. Create the branch. Make sure `.git/info/exclude` has `.dflow/`.
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
   does not see them), and the full `$CLAUDE_CODE_SESSION_ID`.
6. Start the loop: Skill `loop` with args `/dflow 继续无人值守 <slug>`, no
   interval (dynamic). Then run the first round now.

## Round

1. `$S/scripts/run-state.sh check <slug>`:
   - exit 0: go on;
   - exit 3 (`UNLOGGED <sha>`): the last round committed but did not log.
     Rerun its checks; pass, log the row with `commit <sha>`; fail,
     `git revert --no-edit <sha>` and log it as a no-progress round;
   - exit 4: deadline passed, go to **Close**;
   - exit 1 with "lease held by" another session: stop your loop, write
     nothing;
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
   one waiter at a time, never sleep-polling.
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
    condition.

**Gates** (a product or preference call no experiment settles, or a unit that
needs a "will not do" action): log `gate` with question, options, default,
reason, and how to change it; notify. Work on independent units first. Only
when none are left, go ahead on the default: those commits start with
`default:`, and at most one more unit is built on a default before the rest of
its dependents are gated. A unit whose code would stay the same whichever
option is picked (it only calls or combines the defaulted units) does not
depend on the gate; do it normally. A unit that needs a forbidden action is never done
on a default.

**Log** rows: phases `start round gate default dead stage-done side blocked
pause close correction`; append only, fix mistakes with a `correction` row;
decision points, not every command; at least one row per round; plain words
per `references/unslop.md`.

**Notify** with PushNotification only when a `gate` row is written ("需要你
定：<问题>，已先做别的 / 已按默认 <值> 处理") and when the run stops
("<slug> 完成 / 部分完成 / 受阻"). A failed send is not retried; mention it
in the closeout.

## Pause (only when the user says so)

Finish the current step and commit it, or restore it. Only when it can neither
finish nor be restored without losing useful work, commit your own edits as
one `wip:` commit (the one exception to committing only checked units). Log
`pause` with the current unit, the next step, and the traps. Stop the loop,
`run-state.sh release <slug>`. Reply: where it stands, commits, whether the
tree is clean, and the first step on resume.

## Pickup (a new session)

1. `run-state.sh claim <slug>`. Refused because another claude process is
   alive: tell the user to close that session first; stop.
2. `run-state.sh check <slug>` and handle it as in **Round** step 1.
3. Read the manifest; rerun every condition yourself, never trusting a logged
   pass.
4. Log `start` naming the inherited ts range and your full session id. Keep
   the manifest's deadline.
5. A run that paused on a `wip:` commit: verify it or revert it first.
6. Do not redo committed units; find the next step from the log and
   `git log`.
7. `run-state.sh caffeinate <slug>`, start the loop as in **Frame** step 6,
   and run a round.

## Close

1. Uncommitted changes outside `.dflow/`: report them, do not clean.
2. Rerun every condition on the final commit; keep the real output.
3. Timeline: `python3 -I $S/scripts/timeline.py <every session id in the log's
   start rows>` into a directory from `$S/scripts/scratch.sh close`. A missing
   transcript is listed as 未核实.
4. Cross-check: each progress row matches a real commit in
   `git log <base>..HEAD`; each check the log claims appears in the timeline.
   Append `correction` rows for mismatches.
5. Detection, instead of a guard: `run-state.sh scope <slug>` (protected or
   outside-scope files changed); each `.dflow/<slug>-<name>` check script
   against its SHA-256 in the first `start` row; `timeline.py --danger <ids>`
   (forbidden git commands, whole multi-line commands scanned; exit 1 when
   any); remote refs
   against the `start` hash, reported as "未观察到变化" or "有变化" (this
   cannot prove nothing was pushed). Report findings; never roll back on your
   own.
6. Log `close`; the decision column is exactly 完成, 部分完成, or 受阻.
7. Cross-model review: give `codex exec -s read-only` the manifest, the log,
   `git log -p <base>..HEAD`, and the timeline file; ask for decisions with
   thin evidence, checks claimed without a run, choices risky in hindsight,
   and what a quick read would miss. Unavailable: "未审查：<原因>".
8. Stop the loop, `run-state.sh release <slug>` (stops this run's
   caffeinate only), notify.

**Reply:**

```text
**结果**：<完成 / 部分完成 / 受阻> — <一句话>
- 完成条件：<每条 → 最终真实输出>
- 提交：<基线..HEAD，n 个；按默认做的单独列出>
- 按默认做的决定：<问题 → 默认值 → 怎么改（git revert <sha>）>
- 卡住和死路：<单元 → 原因 → 需要你做什么>
- 收尾检测：受保护路径 <未改 / 改了哪些>；范围外文件 <无 / 哪些>；危险命令 <无 / 有哪些>；远端 <未观察到变化 / 有变化>
- 后续事项：<范围外发现；没有就省略>
- 影响面：<见 SKILL.md>
- 日志：.dflow/<slug>.tsv（清单 .dflow/<slug>.md）
**需要你注意**（审查：codex / 未审查：原因）
- <审查要点，最多 5 条>
```
