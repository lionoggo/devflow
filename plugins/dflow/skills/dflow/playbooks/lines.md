### 多线 (lines)

**You own the program, never the code. Register the lines, write their
briefs, collect their receipts, land what is verified at its exact commit.**
From pstack `orchestrate` (its brief, store, ledger, drain and liveness
rules; not its PR stack, stacker, or cloud parts). Principles: 小步可验证,
真实证据, 以现状为准, 结构化教训.

`$S` is this skill's directory. A line is one unit of work given to one
writer (a subagent, a headless agent, or a visible window) in its own
worktree. Saying "多线" approves the worktrees and branches this playbook
creates and removes, as "并行" does in `references/parallel.md`.

Three rules carry the rest:
- A completion is a receipt in a file, not a message. Queue it; handle it at
  the next collection point.
- A running line takes no new instructions. To change its direction, stop
  it and start a new attempt with the full scope.
- Every brief carries `standing.md` verbatim.

## What the main session does

Only three things: the shared prep units the table marks `carrier prep`
(you build and commit them yourself, first, as normal units); writing
briefs; landing verified lines mechanically. A conflicted merge, a rebase,
or any code change is a new line. Never review a diff inline while
collecting: a delivery that needs review gets a verifier line.

Writers per file: the unit table, `ledger.tsv`, `status.md`, and the
decision log `.dflow/<slug>.tsv` are yours alone. A worker writes only its
own report; its decision rows go inside the report, and you copy them into
the log.

## Carriers

Pick by need: a same-host line with no watcher goes to a subagent; another
model family, or work that must survive this session, goes headless; a line
the user wants to watch or that needs a human in a window (a GUI login) is
visible. Every carrier except the Claude subagent gets its worktree from
`$S/scripts/parallel.sh worktree <slug> <id>`; put the printed branch in the
table.

| Carrier | Start | Done when | Stop |
|---|---|---|---|
| subagent, Claude host | Agent with `isolation: "worktree"`, `run_in_background: true`, the brief as prompt; take the branch from the report | it wakes you and the receipt is valid | TaskStop with its id; confirmed when the tool says it stopped |
| subagent, Codex host | `parallel.sh worktree`, then `spawn_agent` (`fork_context: false`) with the brief, its 准备 line replaced by the working-directory line | `wait_agent` returns it and the receipt is valid | `close_agent`; confirmed when it returns |
| headless, either host | `parallel.sh worktree`, then `$S/scripts/agent.sh start <slug> <id> <attempt> <brief> <worktree> [claude\|codex]`; with no model it runs the other host's model; record the pid it prints in `agent` | `agent.sh wait <slug> <id> <attempt> 50 <limit>` prints `delivered <state> <sha\|path>`; pass `<limit>` as twice the brief's time box in seconds (past it the worker is stopped; the default is 3600) | `agent.sh stop <slug> <id> <attempt>`; exit 0 is confirmed, `not stopped: …` is not |
| visible, either host | `parallel.sh worktree`, then `orca agent launch --agent <claude\|codex> --worktree path:<wt> --prompt "<brief text>" --surface terminal --json` (record the terminal handle in `agent`); no Orca: `tmux new-window -c <wt> '<cmd> "<brief text>"'`, where `<cmd>` is `claude --dangerously-skip-permissions` or `codex --dangerously-bypass-approvals-and-sandbox`; neither: print the command for the user to run | `lines.sh receipt <slug> <id> <attempt>` exits 0; the window may stay open | send one stop sentence into the window (Orca terminal send per `orca-cli`, or `tmux send-keys`), or ask the user; confirmed only when its agent process is gone or the user says it stopped |

Headless and visible lines run with permissions fully open, like ccy and cxy;
that is why each gets its own worktree and a brief that forbids everything
outside it. Host details are in `references/hosts.md`.

## Steps

1. **Frame.** Write the done condition as a count ("12 lines landed, each
   with a pass in the ledger at its landed commit"), the number of lines,
   and the time budget. If one agent could finish it inside the budget, stop
   here and use the normal playbook (实施, or 并行 inside it). Present the
   frame once; reversible prep goes on without waiting. Overnight or
   longer than about an hour: frame it as 无人值守 instead, with 多线 as its
   way of working (see **Rounds**).
2. **Ledger.** `$S/scripts/parallel.sh prepare <slug>` (clean tree, as in
   `references/parallel.md`), then `$S/scripts/lines.sh init <slug>`: it
   creates `.dflow/<slug>/` with `ledger.tsv` and an empty `standing.md`, and
   pads an old 10-column table with `carrier model attempt brief report
   progress_at` as `-`. Add one row per line with `lines.sh line set <slug>
   <id> paths=<globs> deps=<ids> state=planned` (it adds a missing row). Run `parallel.sh overlap <slug>` until it passes.
   Write the standing orders before any dispatch: numbered lines, one
   constraint each (model policy, verification bar, forbidden paths, shared
   resources and their lock names). When you catch yourself restating an
   instruction, append it here first.
3. **Pilot.** Run one line end to end: brief, worker, receipt, verification,
   ledger row, landing. Fix the brief template and the verify recipe from
   what it shows before dispatching the rest. For near-identical cheap
   lines, the first line is the pilot, run as a normal line.
4. **Dispatch.** For each ready line (its deps landed): write
   `.dflow/<slug>/briefs/<id>-<attempt>.md` from `references/unit-brief.md`,
   then `lines.sh line set <slug> <id> state=dispatched base=<HEAD>
   carrier=<…> model=<…> attempt=<n> brief=<path> report=<path>
   dispatched_at=<ts>`, then start it per **Carriers**. Keep a rolling
   window of at most about 5 running lines; refill as each one finishes,
   never in blocking batches. Put upstream reports into downstream briefs:
   workers cannot see each other.
5. **Collect.** At each collection point (**When to collect**): read each
   delivery with `lines.sh receipt` (or `agent.sh wait` for headless), copy
   its decision rows into the log, set `state` and `progress_at`, and queue
   verification. Nothing else happens inside a collection.
6. **Verify and land.** Per **Verification** and **Landing**, continuously,
   from the first verified line on. Landing is never a final phase.
7. **Close.** Collect once more. Reconcile every attempt to an end state
   (landed, dead, stopped, or 停止未确认 with what you did about it). Check
   the done condition on the real HEAD. `lines.sh lock show` each resource
   in the standing orders; none should name this slug. Edit shared files
   (README, registries) as a final normal unit. `parallel.sh cleanup <slug>`
   as in `references/parallel.md`. Turn repeated corrections into
   `standing.md` lines or brief-template changes. Then run "复盘 全部" on
   the run's logs. Leave `.dflow/<slug>/` in place: it is the postmortem.

At about 70% of the time budget, dispatch nothing new and land what is
verified.

## Receipts and done

A worker ends every attempt by writing `.dflow/<slug>/reports/<id>-<attempt>.md`
in the main repo (the brief gives its absolute path; a headless line also
has it in `$DFLOW_RECEIPT`). An attempt number runs once: `agent.sh start`
refuses one already used. Its first line is exactly:

```text
RECEIPT <id> <attempt> <done|partial|blocked> <sha|path>
```

Below it: the commands it ran with their output, deviations, decision rows.
After the receipt, the line writes nothing more.

- A line is delivered only when `lines.sh receipt <slug> <id> <attempt>`
  exits 0 for the table's current attempt. A commit on its branch, a log
  line, or a quiet window is a progress signal, never a delivery.
- A read-only line (research, a verifier) delivers a path instead of a SHA.
- `blocked` is not success. `partial` lands only the part its SHA covers,
  after verification like any other.
- A receipt for an older attempt never stands in for the current one; it
  goes to reconciliation only.
- Subagent and headless lines also need their process to have ended
  (`agent.sh wait` prints `exited without receipt` when it ended without
  one: treat that as a failed attempt). A visible line is done on its
  receipt alone.

## Attempts and stopping

`attempt` starts at 1. A new attempt (`attempt` and `tries` both +1) comes
only after the previous one ended or its stop was confirmed. It gets a new
brief, a new report path, and a new worktree: Claude subagents get one
automatically; for the others, remove the old worktree and branch first,
after landing or noting anything useful in them, and `parallel.sh worktree`
makes the new one at the new base. Write what the old attempt found into
the new brief's 上下文. Never resume an old worker to give it new scope.

**Stop protocol:** stop with the carrier's own command (**Carriers**). Only
after it is confirmed, start the next attempt. When the stop cannot be
confirmed, set `state=stop-unconfirmed` and log a `blocked` row:
- its worktree and branch are not reused or removed;
- its resource locks are not taken over (`lines.sh lock` refuses while its
  holder process lives);
- a receipt that arrives later goes to reconciliation only: it is never
  verified or landed on its own;
- the line gets no new attempt until the stop is confirmed (the process is
  gone, or the user says the window is closed).

A stop line at the top of `standing.md` controls later dispatches only. To
make a running line write nothing more, use the stop protocol. When an
outside service fails, stop dispatching the lines that need it and let the
running ones finish or stop.

**Stuck or dead.** The deadline comes from the manifest or the frame;
`progress_at` is the last time you saw progress (a new commit on its branch,
the receipt, a headless output file that grew). A line is stuck only when
it is past its brief's time box with no progress since. Never resume an
agent to check on it; read its branch, its output file, its report.

**Retry by failure mode:** usage cap or out of memory, a smaller scope;
network drop, the same brief again; tool error, another model; unknown, one
retry. Two failed retries: mark the line `dead` and replan around it.

## Shared resources

A resource two lines cannot use at once (a GUI app window, a device, an
outside account) gets a machine-wide lock, shared across repos and
worktrees:
`${DFLOW_LOCK_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dflow/locks}/<resource>/`.
Name each resource in `standing.md`; the brief gives the absolute path of
`lines.sh` and the lock name.

The worker takes, uses, and releases the lock in one shell command, so the
holder is a process that ends with the use:

```text
L=<lines.sh 的绝对路径>; $L lock acquire <资源> <slug>/<id>/<attempt> $$ && <用这项资源的命令>; $L lock release <资源> <slug>/<id>/<attempt>
```

Refused (exit 1): do not do that step; say so in the receipt. A program that
would stay open across commands holding the resource is closed after use.
Only the holder releases; a lock is taken over only when its holder process
is gone. The ledger's write lock (`.dflow/<slug>/.lock`) is separate and
belongs to `lines.sh`.

## Verification

- A line that writes code gets a verifier line on the other model family,
  in a fresh session (headless `agent.sh start` with no model picks it).
  The verifier brief is read-only: it checks out the delivered SHA in its
  own worktree, runs the behavior or the tests, writes nothing in the repo,
  and delivers its report path.
- Record each verdict: `lines.sh ledger record <slug> <id> <attempt> <sha>
  <pass|fail|blocked> <behavior|test|review|self> <verifier> <evidence>`,
  where `<id> <attempt> <sha>` are the verified line's.
- `review` (reading only) never counts as a behavior check. `self` (the
  worker's own run) counts only for a line whose brief says 单命令验证, and
  its evidence starts with `single-command:`. A verifier row overrides a
  self row at the same SHA.
- Verification failed: never re-verify the same SHA as it is. Dispatch a fix
  line (a new attempt of the same line, the failure in its brief); its new
  SHA needs its own pass.
- `blocked` is not a pass; verify again when the cause is gone.

## Landing (by SHA)

One line at a time, in dependency order:

1. Fix the SHA from the receipt.
2. `parallel.sh scope <slug> <id> <sha>`.
3. `lines.sh ledger check <slug> <id> <sha>`: exit 0 or stop here
   (`NOT-PASSED` means verify first).
4. `parallel.sh land <slug> <id> <sha>`: lands `base..<sha>` uncommitted
   in the main tree, never whatever the branch points at now. A note that
   the branch moved past the SHA means commits after the verified one: they
   are not landed; log it and treat them as a new delivery if wanted.
5. Run the line's checks, every finished stage's conditions, and the
   protected checks in the main tree.
6. Pass: `git add` only the line's paths, commit once, `lines.sh line set
   <slug> <id> state=landed landed=<new sha>`.
7. Log a row with `<sha> -> <new sha>` in its evidence.
8. Any failure from step 4 on: `parallel.sh unland <slug> <id>`, then a fix
   line as in **Verification**.

## When to collect

Attended: at the end of a critical section (writing a brief, a landing, a
gate), when a completion notice arrives, and before every report to the
user. A notice that arrives mid-section waits for the section to end.
Begin by reading receipts; end with `lines.sh status <slug>` and its three
lines (counts, changed, gates open). Detail lives in
`.dflow/<slug>/status.md`.

## Rounds (as the way 无人值守 runs)

An unattended run that works in lines keeps the manifest, lease, log, and
loop of `playbooks/unattended.md`; there is no second loop. Each Round,
after `run-state.sh check`: collect (`agent.sh wait` for each headless
line, `lines.sh receipt` for the rest), update `progress_at` and spot stuck
lines, `lines.sh lock show` each standing resource, verify and land what is
ready, refill the window, `lines.sh status <slug>`. A landing commit is
that Round's progress row.

## Recovery (after compaction or a restart)

1. Reread the manifest, `standing.md`, the unit table, `ledger.tsv`, and
   every report not yet reflected in the table or the ledger.
2. Reattach each line by its branch and attempt. Headless: `agent.sh wait`
   (it checks the process identity). Claude subagents die with their
   session: an attempt without a receipt is ended; dispatch a new one.
   Codex subagents and visible windows may still be alive: check before
   starting another attempt.
3. A branch with commits is never done because of them. Only a receipt
   delivers.
4. `lines.sh status <slug>`, then go on from **Collect**.

**Gates** (a product or preference call only the user can make): write a
`gate` row in the decision log (`$S/scripts/log.sh`); the board lists the
open ones. Close it with another `gate` row with the same decision text and
`closed` as its result. Route other work around it.

**Reply** (at checkpoints and at close; numbers from the table and ledger,
not memory):

```text
**多线**：<完成条件> 已达 <n>/<N>（单元表 + 账本）
- <线>（<载体>/<模型>，第 <k> 次）：<进行中 / 已交付 / 已验收 / 已落地 <提交> / 放弃：原因 / 停止未确认>；回执 <done / partial / blocked / 无>；验收 <pass@<提交> / fail / 未验>
- 放弃的线：<线 → 原因；没有就省略>
- 等你定：<问题 → 默认 → 怎么改；没有就写"无">
- 影响面：<见 SKILL.md>
- 账本：.dflow/<slug>/（看板 status.md，验收 ledger.tsv）；单元表 .dflow/<slug>.units.tsv；日志 .dflow/<slug>.tsv
```
