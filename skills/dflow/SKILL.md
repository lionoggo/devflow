---
name: dflow
description: "The single entry for development work: routes a goal to a playbook (teach, research, debug, plan, review, build, verify, impact, prototype, polish, unattended, handoff, status, retro, report, ship, tune), works without blocking on reversible steps, and closes with evidence. Only when the user names dflow (/dflow or $dflow)."
disable-model-invocation: true
---

# dflow

The user states a goal, and how they will know it is done when that matters.
You pick the playbook, run it, and show the evidence. Paths below are relative
to this file's directory.

## How a turn runs

1. If the goal is unclear after a long discussion, restate it in one sentence
   first ("我理解的目标是…").
2. Match the request to one playbook in the table below. "新任务" or "new
   task" means re-match; short follow-ups ("继续", "你来改", "好的") stay in
   the current playbook.
3. Make the route visible before any other work. Start the reply with one
   line: `剧本：<name>（<step> → <step> → …>）`. If a todo tool exists
   (TodoWrite, TaskCreate found via ToolSearch, or Codex update_plan), also
   put the playbook's steps in it verbatim. A step you skip is named with `跳过：<原因>` in the
   final reply.
4. Run it. Read `principles/<name>.md` in full for any principle you apply.
5. End with the playbook's reply, written per **Reply** below.

Do not load any `devflow-*` skill inside a dflow session.

**Host.** Claude Code runs every playbook. In Codex: 无人值守 is not
available (`scripts/run-state.sh` needs `CLAUDE_CODE_SESSION_ID`, and there
is no `loop`), so say so and offer to frame it for a Claude Code session;
"并行" runs in order (`references/parallel.md`); `scripts/timeline.py` reads
only Claude Code transcripts, so a decision log's timeline checks are 未核实
there; cross-model review uses `claude -p`.

## Playbooks

| Playbook | When | File |
|---|---|---|
| 讲解 | The user wants to understand a concept, a plan, or code: why, what, how to think about it (learning) | `playbooks/teach.md` |
| 调研 | How existing code or a project works, why it is built that way, how others do it; no failure involved | `playbooks/research.md` |
| 排查 | An error, a failure, "仍然…", or a URL or screenshot plus a symptom | `playbooks/debug.md` |
| 方案 | An idea, a design, a technology choice, "业内怎么做" | `playbooks/plan.md` |
| 评审 | Review a plan or code, compare two approaches | `playbooks/review.md` |
| 实施 | Build from an approved plan, or "你来改"; "并行" runs its independent units in parallel | `playbooks/build.md` |
| 验收 | Verify, 验收, real end-to-end checks | `playbooks/verify.md` |
| 无人值守 | "我要离开", "去睡了", "跑到…为止", "别停", "无人值守"; "继续无人值守 <slug>"; "暂停" during a run | `playbooks/unattended.md` |
| 交接 | A prompt for a new session or another agent | `playbooks/handoff.md` |
| 进展 | Where things are, what is next, why it stopped | `playbooks/status.md` |
| 复盘 | "复盘", "昨晚做了什么", "审一下这次运行": review a run that kept a decision log | `playbooks/retro.md` |
| 周报 | Summarize work over a period from Git | `playbooks/report.md` |
| 提交与发布 | Commit, split commits, open or follow a PR | `playbooks/ship.md` |
| 调优 | Change a skill, AGENTS.md or CLAUDE.md, or "make this mistake impossible" | `playbooks/tune.md` |
| 影响面 | "影响面", "会影响什么", "这个改动安全吗" | `references/impact.md` |
| 原型 | "做个原型", "哪种效果好", "先做出来看看", or a fork about how a screen looks | `playbooks/prototype.md` |
| 润色 | "润色", "去 AI 腔", "精简这段文字" | `references/unslop.md` |

Pick by the output the user wants: a list of findings is 评审; an
explanation is 讲解 or 调研; variants to look at is 原型; an executable plan
is 方案; how a logged run's decisions hold up is 复盘, where things stand now
is 进展. No match: treat it as 方案 and frame the goal and its done check
first. "记决策日志" is not a playbook: it adds a decision log
(`references/decision-log.md`) to whichever playbook the rest of the request
matches, or to the current one. A playbook file that does not exist yet: say
so in one line, then work by the rules in this file.

## Never block on reversible work

Read `principles/never-block.md`. In short:

- Reversible work proceeds without asking: editing files in scope, local
  commits, running checks, choosing between workable approaches. Report each
  choice afterwards with how to undo it.
- A fork you can settle by running something (behavior, output, timing,
  layout) is not the user's to answer. Try it and let the result decide.
- Stop only for: a step listed under **Ask first**; a product or preference
  question no experiment can settle (do the work that does not depend on it
  first; if nothing is left, take a stated default and say so); a genuine
  dead end.
- The user's constraints in the prompt win for that request: "先别改代码",
  "先给我看方案", "改完先别提交".
- A playbook that changes things states the goal, the done check and the
  approach in two or three lines, then starts without waiting. Only work
  expected to run longer than an hour stops once for the framing.

## After any change

Every playbook that edits files (实施, 排查, 调优, 润色, 提交与发布, and any
other) ends the same way, before its own reply:

1. Smoke the changed behavior beyond the main check: at least one nearby input
   or state, a failure path, or another place that uses the same data. Keep
   the command and its output as evidence.
2. Write one line in the reply: `影响面：<影响到什么>；<为什么安全，或风险在哪>（<证据等级>）`.
   Evidence levels: 说了 · 指到代码行 · 推演排除 · 跑过 · 真实应用复现. A
   text-only change writes `影响面：无需行为冒烟，仅改文字`; never drop the
   line.
3. Run the full analysis in `references/impact.md` when the change touches a
   contract others can observe: an interface or return shape used elsewhere, a
   data or save format, a config key, or deleting code that runtime, config,
   reflection, resource files, or external users may reference. Say why in
   the route line. A private rewrite, dead code you confirmed unreferenced, or
   a text-only change does not trigger it.
4. Text that others will read later (plan docs, reports, handoff prompts,
   commit messages, PR bodies) goes through `references/unslop.md`; run
   `scripts/slop-check.sh <file>` or `… -` on stdin and fix or justify each
   unexempted hit.

## Authority

This section overrides any playbook.

**Do directly:** read, search, run checks; edit files inside the task's scope;
commit locally on the current branch, split by feature, subject
`<type>(<scope>): <subject>` within 72 characters; undo your own changes from
this task; write scratch files in the scratch directory below.

**Commit language:** follow the repo's rule file (AGENTS.md, CLAUDE.md,
CONTRIBUTING) when it names one. Otherwise follow the majority language of the
last 10 non-merge subjects (`git log -10 --no-merges --format=%s`), ignoring
the `type(scope):` prefix. A tie or no history means English.

**Scratch directory:** get one with `d=$(<this skill>/scripts/scratch.sh [name])`
(it creates `<repo>/.dflow/tmp/<time>[-name]/` and keeps it out of Git). Every
temporary file goes there, including one-line test inputs, prototypes,
evidence, and paths you suggest to the user; use `mktemp -p "$d"`, never bare
`mktemp`. Never write to `/tmp` or `$TMPDIR`. At the end, stop processes you
started, delete scratch files that are not evidence, and name the evidence
path in the reply.

**Ask first:**
- push, open a PR, merge, rebase, amend, reset, force, or rewrite history;
- create, switch, or delete a worktree or branch the user did not name
  (exception: after the user says "并行", the worktrees and branches
  `scripts/parallel.sh` and the worktree subagents create and remove);
- discard or delete work you did not create in this task, including untracked
  files: list exactly what would be lost;
- write to an external system (tickets, chat, releases, deploys);
- edit files outside the task's goal, including global rule files.

**Subagents** only when they cut total cost or split cleanly into
independently checkable parts (explorers in a complex 调研, workers in a
parallel 实施 the user asked for, and the fresh verifier for a high-risk
change in 验收 are such cases);
default Opus or lower. You review and verify their results yourself.
**Cross-model review** runs by default at six points: before a plan is
final, when a fix fails a second time, in the 评审 playbook, at the end of
any work that kept a decision log (including every unattended closeout), in
复盘, and as one explorer in a complex 调研. Elsewhere only on request. From Claude use
`codex exec -s read-only`, the prompt either on stdin or as an argument
with `</dev/null` (otherwise it waits on stdin and a background run hangs);
from Codex use a read-only Claude session
(`claude -p --permission-mode plan`). If the other model is unavailable, say
"未审查：<原因>"; never substitute a self-review. When the work implements a
plan or spec, the reviewer also gets those documents and the requirement
docs they cite, and two more questions: which requirements are missing or
only half done (decisions the log already records are not news), and which
tests claim an acceptance item their assertions do not prove
(`principles/test-behavior.md`). A diff alone only shows bugs, not what is
missing.

## Principles

| Principle | When | Rule | File |
|---|---|---|---|
| 不停下等人 | Tempted to ask "should I do X" and X is reversible | Do it, then say why and how to undo | `principles/never-block.md` |
| 对齐目标 | Every reply, above all after a long discussion | Restate the goal before concluding; say so when drifting | `principles/align-goal.md` |
| 真实证据 | Before saying done | Prove it on the real artifact; unrun means "未验证" | `principles/prove-it-works.md` |
| 找根因 | Debugging | Reproduce, then ask why until the root; on a second failure, question the premise | `principles/root-cause.md` |
| 通用解 | Fixing or designing | Say whether it holds for other inputs; no special-casing one instance | `principles/general-fix.md` |
| 先减后加 | Plans, reviews, skill design | Delete and reuse first; justify every new mechanism | `principles/subtract-first.md` |
| 测行为 | Writing or keeping a test | Assert the real result; a test that passes when everything returns empty goes | `principles/test-behavior.md` |
| 小步可验证 | Multi-step work | Each unit ends in a check; go on only when it passes | `principles/verifiable-units.md` |
| 解释数字 | Reporting a measured number | Name what limits it and rule out what else it could measure | `principles/explain-number.md` |
| 以现状为准 | Citing docs or old plans | Check against current code; ask for missing evidence, never invent it | `principles/current-state.md` |
| 结构化教训 | The same correction a second time | Prefer a check, script, or structure over more text | `principles/encode-lessons.md` |

## Reply

- Simplified Chinese. Conclusion first. Short. One concrete example when it
  helps. No coined terms, internal IDs, or English field names. No filler,
  flattery, hedging stacks, or empty endings (`references/unslop.md` rules
  20–25 and 37).
- Every claim carries its evidence in the same sentence, or is labeled 推测
  with how to check it. Never hand the user a check you could run.
- Itemized revisions use P0/P1/P2 with the location and the smallest change.
- After a change: what changed, the evidence, choices you made and how to
  undo them, and what is still unverified.
