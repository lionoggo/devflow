### 多线 (lines)

**You run the program, never the code. Decide which line does each piece of
work, then check what each one produces, and land it at the exact commit
that passed.** From pstack `orchestrate` (0.15.36: run it with your own
tools, no relaying between agents; not its PR stack or cloud parts).
Principles: 小步可验证, 真实证据, 以现状为准.

`$S` is this skill's directory. A line is one unit of work given to one
writer (a subagent, a headless agent, or a visible window) in its own
worktree. Saying "多线" or "并行", or asking for separate worktrees, approves
the worktrees and branches this playbook creates and removes, as "并行" does
in `references/parallel.md`. A request routed here without any of these gets
its frame with the line plan and "说"多线"即同意为这些线各建一个 worktree"
before any worktree is made. The mechanics (receipts, attempts and the stop
protocol, shared-resource locks, the ledger, landing failures, recovery) are
in `references/lines-mechanics.md`; read the part you reach.

## Topology

- **One writer per line.** Each line has its own worktree and branch, and
  only its worker writes there. You write the unit table, the ledger, and
  the decision log `.dflow/<slug>.tsv`; a worker writes only its own report,
  and you copy its decision rows into the log (phase `decision`,
  `<id>/<attempt>` at the head of the evidence).
- **You never edit code.** You build only the shared prep units the table
  marks `carrier prep`, first; a conflicted merge, a rebase, a shared file
  edited at the end (README, registries), or any other code change is a new
  line.
- **A fresh worker per independent task.** Its brief carries everything it
  needs, each upstream report it depends on pasted in full: workers cannot
  see each other. Work coupled at run time (one state machine, an animation
  and its controller, an extraction and the design read from it) stays in
  one line, or its shared contract lands first as a prep unit.
- **A running line takes no new instructions.** To change its direction,
  stop it and start a new attempt with the full scope. Never message a
  worker to check on it. Waiting is one background waiter per running
  line that wakes you (headless: a background shell repeating `agent.sh
  wait` until it prints something other than `running`; Codex host: the
  matching row of `references/hosts.md`), or the next Round; never a
  sleep loop in the main session.
- **A verifier is never the author and runs on the other model family**
  (claude → codex, codex → claude), named explicitly.
- **Start with one line.** Take it through brief, worker, receipt,
  verification, and landing before the rest, so a flaw in the brief costs
  one line, and fix the brief template and the verify recipe from what it
  shows. For near-identical cheap lines, the first line is that pilot. Then keep at most about 5 running, starting the next as each one
  ends, never in blocking batches.

## Carriers

Default to a background carrier: a same-host line goes to a subagent;
another model family, or work that must survive this session, goes headless.
A line is visible only when the user asks to watch it ("可见", "开窗口") or
it needs a human in a window (a GUI login). Every carrier except the Claude
subagent gets its worktree from `$S/scripts/parallel.sh worktree <slug>
<id>`; put the printed branch in the table.

| Carrier | Start | Done when | Stop |
|---|---|---|---|
| subagent, Claude host | Agent with `isolation: "worktree"`, `run_in_background: true`, the brief as prompt; take the branch from the report | it wakes you and the receipt is valid | TaskStop with its id; confirmed when the tool says it stopped |
| subagent, Codex host | `parallel.sh worktree`, then `spawn_agent` (`fork_context: false`) with the brief, its 准备 the working-directory form (`references/unit-brief.md`) | `wait_agent` returns it and the receipt is valid | `close_agent`; confirmed when it returns |
| headless, either host | `parallel.sh worktree`, then `$S/scripts/agent.sh start <slug> <id> <attempt> <brief> <worktree> <claude\|codex>:<model> <limit>`, the model named (without it the CLI default runs; Claude's was Sonnet in the 2026-11-09 pilot, refused twice), `<limit>` twice the brief's time box in seconds (default 7200; the run keeps that deadline itself); record the pid it prints in `agent` | `agent.sh wait <slug> <id> <attempt> 50 <limit>` prints `delivered <state> <sha\|path>` (same `<limit>`; `running (timeout, not stopped)` is 停止未确认) | `agent.sh stop <slug> <id> <attempt>`; exit 0 is confirmed, `not stopped: …` is not |
| visible, either host | `parallel.sh worktree`, then `orca agent launch --agent <claude\|codex> --worktree path:<wt> --prompt "<brief text>" --surface terminal --json` (record the terminal handle in `agent`); no Orca: `tmux new-window -c <wt> '<cmd> "<brief text>"'`, `<cmd>` being `claude --dangerously-skip-permissions` or `codex --dangerously-bypass-approvals-and-sandbox`; neither: print the command for the user | `lines.sh receipt <slug> <id> <attempt>` exits 0 | send one stop sentence into the window, or ask the user; confirmed only when its agent process is gone or the user says it stopped |

Headless and visible lines run with permissions fully open, like ccy and cxy;
that is why each gets its own worktree and a brief that forbids everything
outside it (`references/hosts.md`). A visible Claude line in a new worktree
first waits on "Is this a project you trust" with no output: read its window
once after the start, and when it sits there, ask the user to confirm it;
never press it yourself or edit the trust settings.

## Supervision

- **Each brief names the evidence that proves the line done** (a command
  and its expected output, a control-skill check, an artifact), the goal
  restated, the paths it may and may not write, and the actions it must not
  take (`references/unit-brief.md`). A field you cannot fill is a line not
  yet scoped: do not dispatch it.
- **Read the diff or the artifact, not only the report.** A green test run
  is an input to a verdict, not the verdict. A verdict covers one SHA.
- **Send back drift.** Work outside the brief's scope, or grown past what
  was asked, goes back as a new attempt; keep only what the goal needs and
  park the rest as follow-ups.
- **Check live state before you report** (the line's branch, its receipt,
  `agent.sh peek`), not the last thing a worker said. Account for every
  attempt you started: landed, done, dead, or stopped.
- **Judge a stall by output, not status text** (a new commit, the receipt,
  a headless output file that grew). A line is stuck only past its brief's
  time box with no progress. Retry by cause: a smaller scope after a usage
  cap or out of memory, the same brief after a network drop, another model
  after a tool error, one retry when unknown. After two failed retries, mark
  it `dead` and replan around it.
- **Ask the user only for a real decision or a blocker** (a `gate` row via
  `$S/scripts/log.sh`, closed by a later `gate` row with the same decision
  and result `closed`); route other work around it. Retries, rebases, and
  "should I keep going" never reach the user.

## Steps

1. **Frame.** The done condition as a count ("12 lines landed, each with a
   pass in the ledger at its source SHA and a `commit <landed sha> from
   <source sha>` row in the log"), the lines, and the time budget. If one
   agent could finish it inside the budget, use the normal playbook (实施,
   or 并行 inside it). Split only into lines that each still work, and can
   be verified, when landed alone. Present the frame once; reversible prep goes on
   without waiting. Overnight or longer than about an hour: frame it as
   无人值守, with 多线 as its way of working (**Rounds** below).
2. **Prepare.** Write the manifest `.dflow/<slug>.md` in the format of
   `playbooks/unattended.md` (On "开始" step 3: `slug`, `base`, `deadline`,
   `allow`, `protect`, then goal and acceptance; `protect: -` means nothing
   is protected), attended runs too: recovery rereads it, and `parallel.sh
   overlap` refuses to run without it. No manifest, no dispatch. Then
   `$S/scripts/parallel.sh prepare <slug>`, `$S/scripts/lines.sh init
   <slug>`, one `lines.sh line set <slug> <id> paths=<globs> deps=<ids>
   state=planned` per line, and `parallel.sh overlap <slug>` until it
   passes. Every shared resource two lines cannot use at once is named in
   `.dflow/<slug>/standing.md` with its lock name
   (`references/lines-mechanics.md` **Shared resources**); other constraints
   every brief must repeat (model policy, verification bar) go there too,
   when there are any.
3. **Dispatch** each ready line (its deps landed): write
   `.dflow/<slug>/briefs/<id>-<attempt>.md` from `references/unit-brief.md`,
   `lines.sh line set <slug> <id> state=dispatched base=<HEAD> carrier=<…>
   model=<…> attempt=<n> brief=<path> report=<path> dispatched_at=<ts>`, then
   start it per **Carriers** and set `branch=` to the branch it printed or
   reported (`parallel.sh land` refuses a line without one).
4. **Collect** when a line wakes you and before every report to the user:
   read each delivery (`lines.sh receipt`, or `agent.sh wait` for headless),
   copy its decision rows into the log, set `state` and `progress_at`.
   Delivery rules: `references/lines-mechanics.md` **Receipts**. To look
   without writing anything: `lines.sh status <slug> --print`.
5. **Verify and land,** from the first delivered line on; landing is never a
   final phase. When the line's check is one cheap command, the brief names
   it (`验证     单命令验证：<命令>`), the worker reports its output, and
   you spot-check it. Expensive, judgment-laden (animation, game feel, a
   design read from code), or wide-impact work gets a verifier line `v-<id>`
   (`paths=-`, `base=<the SHA it verifies>`, its own `parallel.sh worktree`,
   read-only, checking the line's 验收 items one by one, an unchecked one
   making it `blocked`). Record each verdict with `lines.sh ledger record`;
   a failed SHA is never re-verified as it is, it gets a fix attempt. Land
   one line at a time in dependency order: `parallel.sh land <slug> <id>
   <sha>` (it checks scope, the ledger, and the receipt, and refuses a branch
   that moved), run the line's checks, every finished stage's conditions,
   and the protected checks in the main tree without leaving files behind, then `git add` only the line's paths,
   commit once, then `parallel.sh landed <slug> <id>`: it sets `state=landed
   landed=<new sha>` and logs `commit <new sha> from <sha>` (never set these by
   hand; `lines.sh` refuses `state=landed` without a landed commit). A failure:
   `references/lines-mechanics.md` **Landing failures**.
6. **Close.** Collect once more; bring every attempt to an end state
   (landed, dead, stopped, or 停止未确认 with what you did about it). Shared
   files go to one more line after the lines they depend on land. On the
   final HEAD, check the done condition and every acceptance item of the
   manifest one by one with its evidence (the per-line passes do not add up
   to this). Delete `refs/dflow/<slug>/` refs of landed or dead lines;
   `lines.sh lock show` each resource in `standing.md` names no line of this
   slug; `parallel.sh cleanup <slug>` and name what it keeps. Then run
   "复盘 <slug>". Leave `.dflow/<slug>/` in place: it is the postmortem.

At about 70% of the time budget, dispatch nothing new and land what is
verified.

## Rounds (as the way 无人值守 runs)

An unattended run that works in lines keeps the manifest, lease, log, and
loop of `playbooks/unattended.md`; there is no second loop. Its Round,
Pause, Pickup, and Close are the 多线 branches there.

**Reply** (at checkpoints and at close; numbers from the table and ledger,
not memory):

```text
**多线**：<完成条件> 已达 <n>/<N>（账本的来源提交 pass + 日志的来源→落地映射）
- 目标：<用户的目标，一句话>
- <线>（<载体>/<模型>，第 <k> 次）：<进行中 / 已交付 / 已验收 / 已落地 <提交> / 放弃：原因 / 停止未确认>；验收 <pass@<提交> / fail / 未验>
- 验收线：<v-<线>（<模型>，第 <k> 次）：进行中 / 已交付 / 停止未确认；没有就省略>
- 放弃的线：<线 → 原因；没有就省略>
- 等你定：<问题 → 默认 → 怎么改；没有就写"无">
- 影响面：<见 SKILL.md>
- 记录：.dflow/<slug>/（账本 ledger.tsv）；日志 .dflow/<slug>.tsv
```
