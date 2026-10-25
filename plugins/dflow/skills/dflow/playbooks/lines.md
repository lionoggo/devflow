### 多线 (lines)

**You own the program, never the code. Register the lines, write their
briefs, collect their receipts, land what is verified at its exact commit.**
From pstack `orchestrate` (its brief, store, ledger, drain and liveness
rules; not its PR stack, stacker, or cloud parts). Principles: 小步可验证,
真实证据, 以现状为准, 结构化教训.

`$S` is this skill's directory. A line is one unit of work given to one
writer (a subagent, a headless agent, or a visible window) in its own
worktree. Saying "多线" or "并行", or asking for separate worktrees, approves
the worktrees and branches this playbook creates and removes, as "并行" does
in `references/parallel.md`. A request routed here without any of these gets
its frame with the line plan and "说"多线"即同意为这些线各建一个 worktree"
before any worktree is made.

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
a shared file edited at the end (README, registries), or any other code
change is a new line, registered in the table like the rest; you never
edit them yourself. Never review a diff inline while collecting: a delivery
that needs review gets a verifier line.

Writers per file: the unit table, `ledger.tsv`, `status.md`, and the
decision log `.dflow/<slug>.tsv` are yours alone. A worker writes only its
own report; its decision rows go inside the report, and you copy them into
the log with phase `decision` and `<id>/<attempt>` at the head of the
evidence.

## Carriers

Default to a background carrier: a same-host line goes to a subagent;
another model family, or work that must survive this session, goes headless.
A line is visible only when the user asks to watch it ("可见", "开窗口") or
it needs a human in a window (a GUI login); to look at a background line, use
`agent.sh peek` or `lines.sh status --print`. Every carrier except the Claude subagent gets its worktree from
`$S/scripts/parallel.sh worktree <slug> <id>`; put the printed branch in the
table.

| Carrier | Start | Done when | Stop |
|---|---|---|---|
| subagent, Claude host | Agent with `isolation: "worktree"`, `run_in_background: true`, the brief as prompt; take the branch from the report | it wakes you and the receipt is valid | TaskStop with its id; confirmed when the tool says it stopped |
| subagent, Codex host | `parallel.sh worktree`, then `spawn_agent` (`fork_context: false`) with the brief, its 准备 the working-directory form (`references/unit-brief.md`) | `wait_agent` returns it and the receipt is valid | `close_agent`; confirmed when it returns |
| headless, either host | `parallel.sh worktree`, then `$S/scripts/agent.sh start <slug> <id> <attempt> <brief> <worktree> [claude\|codex]`; it refuses a brief whose first line is not `dflow 线 <slug>/<id>/<attempt>` for these arguments, and an attempt already claimed; with no model it runs the other host's model; record the pid it prints in `agent` | `agent.sh wait <slug> <id> <attempt> 50 <limit>` prints `delivered <state> <sha\|path>`; pass `<limit>` as twice the brief's time box in seconds (past it the worker is stopped when its identity checks out, and only reported when it cannot; the default is 3600) | `agent.sh stop <slug> <id> <attempt>`; exit 0 is confirmed, `not stopped: …` is not |
| visible, either host | `parallel.sh worktree`, then `orca agent launch --agent <claude\|codex> --worktree path:<wt> --prompt "<brief text>" --surface terminal --json` (record the terminal handle in `agent`); no Orca: `tmux new-window -c <wt> '<cmd> "<brief text>"'`, where `<cmd>` is `claude --dangerously-skip-permissions` or `codex --dangerously-bypass-approvals-and-sandbox`; neither: print the command for the user to run | `lines.sh receipt <slug> <id> <attempt>` exits 0; the window may stay open | send one stop sentence into the window (Orca terminal send per `orca-cli`, or `tmux send-keys`), or ask the user; confirmed only when its agent process is gone or the user says it stopped |

Headless and visible lines run with permissions fully open, like ccy and cxy;
that is why each gets its own worktree and a brief that forbids everything
outside it. Host details are in `references/hosts.md`.

A visible line's first look comes at the first collection after its start:
read its window (`tmux capture-pane -p -t <target>`, or the Orca terminal
read per `orca-cli`). Claude Code asks "Is this a project you trust" the
first time it enters a new worktree, and the line waits there with no
output. When it sits on that prompt, ask the user to confirm it in the
window; never press it yourself or edit the trust settings. Headless lines
do not stop there (measured 2026-10-24).

Without `ps`, a process's identity cannot be checked: `agent.sh` then sends
no signal. `wait` still reports whether it lives and when it is past its
limit, but does not stop it; `stop` prints `not stopped: …`.

## Steps

1. **Frame.** Write the done condition as a count ("12 lines landed, each
   with a pass in the ledger at its source SHA and a `commit <landed sha> from
   <source sha>` row in the log"), the number of lines, and the time budget. If one
   agent could finish it inside the budget, stop here and use the normal
   playbook (实施, or 并行 inside it). Present the frame once; reversible
   prep goes on without waiting. Overnight or longer than about an hour:
   frame it as 无人值守 instead, with 多线 as its way of working (see
   **Rounds**).
2. **Ledger.** Write the manifest `.dflow/<slug>.md` in the format of
   `playbooks/unattended.md` (On "开始" step 3): a `key: value` block with
   `slug`, `base`, `deadline` (the time budget as an absolute UTC time),
   `allow` and `protect`, then the goal and the acceptance in prose. An
   attended run writes it too: recovery rereads it, and `parallel.sh
   overlap` refuses to run without it or without `allow` (`protect: -`
   means nothing is protected). No manifest, no dispatch. Then `$S/scripts/parallel.sh prepare <slug>` (clean tree,
   as in `references/parallel.md`), then `$S/scripts/lines.sh init <slug>`: it
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
   verification. A visible line's first collection also reads its window
   (**Carriers**). Nothing else happens inside a collection.
6. **Verify and land.** Per **Verification** and **Landing**, continuously,
   from the first verified line on. Landing is never a final phase.
7. **Close.** Collect once more. Reconcile every attempt to an end state
   (landed, dead, stopped, or 停止未确认 with what you did about it). Check
   the done condition on the real HEAD. `lines.sh lock show` each resource
   in the standing orders; none should name this slug. Shared files
   (README, registries) go to one more registered line after the lines they
   depend on land, verified and landed like the rest. `parallel.sh cleanup
   <slug>` removes only lines in state `landed`, `done`, `dead`, `stopped`,
   or `planned` (never dispatched); it keeps and lists `dispatched`,
   `stop-unconfirmed`, any other state, and a landed line whose branch has
   commits past what landed. Name the kept ones in the reply. Its ignored
   and untracked file rules are those of `references/parallel.md`. Turn repeated corrections into
   `standing.md` lines or brief-template changes. Then run "复盘 全部" on
   the run's logs. Leave `.dflow/<slug>/` in place: it is the postmortem.

At about 70% of the time budget, dispatch nothing new and land what is
verified.

## Receipts and done

A worker ends every attempt by publishing `.dflow/<slug>/reports/<id>-<attempt>.md`
in the main repo (the brief gives its absolute path; a headless line also
has it in `$DFLOW_RECEIPT`). An attempt number runs once: `agent.sh start`
claims it atomically (`.dflow/<slug>/run/<id>-<attempt>.claim`) and refuses
one already claimed, also when two starts race. The report's first line is
exactly:

```text
RECEIPT <id> <attempt> <done|partial|blocked> <sha|path>
```

Below it: the commands it ran with their output, deviations, decision rows.
The worker writes the whole report to `<report>.tmp` first, then moves it
into place in one step (`mv <report>.tmp <report>`). The file at the report
path appearing is the delivery; after that, the line writes nothing more,
the report included.

- A line is delivered only when `lines.sh receipt <slug> <id> <attempt>`
  exits 0 for the table's current attempt. It reads only the report path,
  never `<report>.tmp`: a `.tmp` alone is not a delivery. A commit on its
  branch, a log line, or a quiet window is a progress signal, never a
  delivery.
- A read-only line (research, a verifier) delivers a path instead of a SHA.
  It is done on its receipt; it never goes into the ledger, which holds
  commits only. Set its state to `done`.
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
confirmed (no `ps` to check the process identity counts as unconfirmed),
set `state=stop-unconfirmed` and log a `blocked` row:
- its worktree and branch are not reused or removed (`parallel.sh cleanup`
  keeps them);
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
Name each resource in `standing.md`; the brief's 资源 field gives the
absolute path of `lines.sh`, the lock directory resolved to an absolute
path, and the lock name.

The worker takes, uses, and releases the lock in one shell command, so the
holder is a process that ends with the use. `lock acquire` prints a token on
success; `lock release` frees the lock only for that token, so a release
can never free a lock someone else holds:

```text
export DFLOW_LOCK_DIR=<锁目录绝对路径>; L=<lines.sh 的绝对路径>; tok=$($L lock acquire <资源> <slug>/<id>/<attempt> $$) || exit 1; <用这项资源的命令>; rc=$?; $L lock release <资源> "$tok"; exit $rc
```

The command's exit code is the resource command's. Refused (exit 1): the
resource step did not run and nothing is released; say so in the receipt.
The resource command must not leave a process behind that keeps using the
resource after the shell exits: a program that would stay open across
commands is closed inside the same command. A lock is taken over only when
its holder process is gone. The ledger's write lock
(`.dflow/<slug>/.lock`) is separate and belongs to `lines.sh`.

## Verification

- A line that writes code gets a verifier line on the other model family
  than the verified line's `model` column (claude → codex, codex → claude),
  in a fresh session. Name that model explicitly (`agent.sh start … <model>`,
  or the matching visible command); never rely on the default, which is
  picked against the main session's host, not against the worker.
- A verifier line is a line of its own: id `v-<id>`, a row in the table
  with `paths=-` (writes nothing; overlap and scope treat it so) and
  `base=<the SHA it verifies>`, then `parallel.sh
  worktree <slug> v-<id>` and its printed branch in `branch`, so cleanup
  does not take it for an orphan. Its brief is read-only: it runs the
  behavior or the tests in that worktree, writes nothing in the repo, and
  delivers its report path. The `v-` prefix sets verifier lines apart on
  the board; the reply lists them on their own line.
- Record each verdict: `lines.sh ledger record <slug> <id> <attempt> <sha>
  <pass|fail|blocked> <behavior|test|review|self> <verifier> <evidence>`,
  where `<id> <attempt> <sha>` are the verified line's. The SHA must name
  exactly one commit; the ledger keeps the full SHA, and a short one that
  does not resolve, or resolves to several, is refused.
- At one SHA, when any row is not `self` (behavior, test, review), the last
  of those decides. A `review` row (reading only) can fail a SHA but its pass
  is ignored, so it neither passes nor overrides a behavior or test pass. Only
  when there is no such row does a `self` pass count, and only when the
  line's brief (its `brief` column, or `.dflow/<slug>/briefs/<id>-<attempt>.md`)
  has its own line `验证     单命令验证：<命令>` (a mention elsewhere, or
  "禁止单命令验证", does not count) and the evidence starts with
  `single-command:`. A self
  row added after a verifier's fail never turns it into a pass.
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
   in the main tree. It refuses when the line's branch head is no longer
   that SHA: the branch changed after verification. Log it; the branch's
   new head is a new delivery that needs its own pass (a new attempt when
   the worker kept writing after its receipt).
5. Run the line's checks, every finished stage's conditions, and the
   protected checks in the main tree, without leaving files behind
   (`PYTHONDONTWRITEBYTECODE=1` for Python, output directories outside the
   repo): an untracked file in the main tree makes the next `land` refuse.
   An untracked file these checks did produce: list it, then delete it.
   One they did not produce goes to the user first, per **Ask first** in
   `SKILL.md`.
6. Pass: `git add` only the line's paths, commit once, `lines.sh line set
   <slug> <id> state=landed landed=<new sha>`.
7. Log a row whose evidence is `commit <new sha> from <sha>` (the
   `commit <sha>` form is what `run-state.sh check` reads, so an unattended
   round does not flag the landing as unlogged). This row and the ledger's
   pass at `<sha>` together count the line toward the done condition.
8. Any failure from step 4 on: `parallel.sh unland <slug> <id>`, then a fix
   line as in **Verification**.

## When to collect

Attended: at the end of a critical section (writing a brief, a landing, a
gate), when a completion notice arrives, and before every report to the
user. A notice that arrives mid-section waits for the section to end.
Begin by reading receipts; end with `lines.sh status <slug>` and its three
lines (counts, changed, gates open). Detail lives in
`.dflow/<slug>/status.md`: per line its state, attempt, last progress,
receipt, and verdict, the open gates, and the latest `decision` rows you
copied from reports. Blockers and the workers' own calls reach the board
only through those rows. To look without writing anything (进展, or any
read from outside the run), use `lines.sh status <slug> --print` and
`agent.sh peek <slug> <id> <attempt>`: no file, no snapshot, no lock, no
signal. `running (identity unverified)` from `peek` or `wait` means the
process is alive but cannot be proven to be this attempt (no `ps`, or its
record lacks the identity): treat it as running, never as ended, and never
stop or restart it; when it lasts past the time box, mark the line
`stop-unconfirmed` and ask the user. The board's 验收 column is the
effective verdict (what `ledger check` decides); "原始最新" is only the last
raw ledger row.

## Rounds (as the way 无人值守 runs)

An unattended run that works in lines keeps the manifest, lease, log, and
loop of `playbooks/unattended.md`; there is no second loop. Each Round,
after `run-state.sh check`: collect (`agent.sh wait` for each headless
line, `lines.sh receipt` for the rest), update `progress_at` and spot stuck
lines, `lines.sh lock show` each standing resource, verify and land what is
ready, refill the window, `lines.sh status <slug>`. A landing commit is
that Round's progress row. Pause, Pickup, and Close of such a run have
their 多线 branches in `playbooks/unattended.md`.

## Recovery (after compaction or a restart)

1. Reread the manifest, `standing.md`, the unit table, `ledger.tsv`, and
   every report not yet reflected in the table or the ledger.
2. Reattach each line by its branch and attempt. Headless: `agent.sh peek`
   (it checks the process identity and sends no signal; `wait` could stop
   a worker past its limit). Claude subagents die with their
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
**多线**：<完成条件> 已达 <n>/<N>（账本的来源提交 pass + 日志的来源→落地映射）
- <线>（<载体>/<模型>，第 <k> 次）：<进行中 / 已交付 / 已验收 / 已落地 <提交> / 放弃：原因 / 停止未确认>；回执 <done / partial / blocked / 无>；验收 <pass@<提交> / fail / 未验>
- 验收线：<v-<线>（<模型>，第 <k> 次）：进行中 / 已交付 / 停止未确认；没有就省略>
- 放弃的线：<线 → 原因；没有就省略>
- 等你定：<问题 → 默认 → 怎么改；没有就写"无">
- 影响面：<见 SKILL.md>
- 账本：.dflow/<slug>/（看板 status.md，验收 ledger.tsv）；单元表 .dflow/<slug>.units.tsv；日志 .dflow/<slug>.tsv
```
