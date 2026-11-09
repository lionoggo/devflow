# 多线 mechanics

The parts of `playbooks/lines.md` a run reaches only in their case, moved
here when that playbook was cut down (pstack 0.15.36), unchanged except for
cross-references and the unland trigger now named by what happened. The scripts
enforce most of them; their headers (`scripts/lines.sh`, `scripts/agent.sh`,
`scripts/parallel.sh`) hold the exact rules.

## Receipts

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

`agent.sh start` refuses a brief whose first line is not `dflow 线
<slug>/<id>/<attempt>` for its arguments, and an attempt already claimed.
With no model it runs the other host's model, so a verifier line always
names its model. `agent.sh wait` without a `<limit>` uses 3600 seconds; past
the limit the worker is stopped when its identity checks out, and only
reported when it cannot.

## Process identity

Without `ps`, a process's identity cannot be checked: `agent.sh` then sends
no signal. `wait` still reports whether it lives and when it is past its
limit, but does not stop it; `stop` prints `not stopped: …`.

`running (identity unverified)` from `agent.sh peek` or `wait` means the
process is alive but cannot be proven to be this attempt (no `ps`, or its
record lacks the identity): treat it as running, never as ended, and never
stop or restart it; when it lasts past the time box, mark the line
`stop-unconfirmed` and ask the user.

## Attempts and stopping

`attempt` starts at 1. A new attempt (`attempt` and `tries` both +1) comes
only after the previous one ended or its stop was confirmed. It gets a new
brief, a new report path, and a new worktree: Claude subagents get one
automatically; for the others, remove the old worktree and branch first,
after landing or noting anything useful in them, and `parallel.sh worktree`
makes the new one at the new base. When the old attempt's commits are worth
keeping (a fix attempt after a failed verdict, a delivery cut off by its
time box), keep them first with `git update-ref refs/dflow/<slug>/<id>-<old
attempt> <its head>` (a ref, no branch or worktree), and make the new
brief's 准备 apply them after the switch to base: `git cherry-pick <old
base>..<that ref>`, spelled with literal SHAs; conflicts are the worker's
to resolve inside its paths. Write what the old attempt found into
the new brief's 上下文. Close deletes these refs (`git update-ref -d`)
once their line landed or died. Never resume an old worker to give it new scope.

**Stop protocol:** stop with the carrier's own command (`playbooks/lines.md` **Carriers**). Only
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

## Shared resources

A resource two lines cannot use at once (a GUI app window, a device, an
outside account) gets a machine-wide lock, shared across repos and
worktrees:
`${DFLOW_LOCK_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dflow/locks}/<resource>/`.
Name each resource in `standing.md`; the brief's 资源 field gives the
absolute path of `lines.sh`, the lock directory resolved to an absolute
path, and the lock name.

A use that fits in one shell command takes, uses, and releases the lock in
that command, so the holder is a process that ends with the use. `lock acquire` prints a token on
success; `lock release` frees the lock only for that token, so a release
can never free a lock someone else holds:

```text
export DFLOW_LOCK_DIR=<锁目录绝对路径>; L=<lines.sh 的绝对路径>; tok=$($L lock acquire <资源> <slug>/<id>/<attempt> $$) || exit 1; <用这项资源的命令>; rc=$?; $L lock release <资源> "$tok"; exit $rc
```

The command's exit code is the resource command's. Refused (exit 1): the
resource step did not run and nothing is released; say so in the receipt.
The resource command must not leave a process behind that keeps using the
resource after the shell exits: a program that would stay open across
commands is closed inside the same command.

A use that spans several tool calls (a Godot or browser check driven
through MCP) holds the lock from its first call to its last: a headless
line passes `$DFLOW_HOLDER_PID` (its agent process, set by `agent.sh`)
instead of `$$`, acquires before the first call, releases with the token
after closing the app, and writes the token into its receipt notes. A
subagent or visible line has no such pid: it uses only the one-command form,
or the resource goes to one headless line that drives it for every line in
turn. A resource that cannot be isolated is driven by one line at a time,
never two. A lock is taken over only when
its holder process is gone. The ledger's write lock
(`.dflow/<slug>/.lock`) is separate and belongs to `lines.sh`.

## Ledger

- Record each verdict: `lines.sh ledger record <slug> <id> <attempt> <sha>
  <pass|fail|blocked> <behavior|test|review|self> <verifier> <evidence>`,
  where `<id> <attempt> <sha>` are the verified line's. The SHA must name
  exactly one commit; the ledger keeps the full SHA, and a short one that
  does not resolve, or resolves to several, is refused.
- At one SHA, any `fail` that is not `self` decides: a later pass of any
  kind never turns it back (a new SHA does). With no such fail, the last row
  that is not `self` (behavior, test, review) decides. A `review` row
  (reading only) can fail a SHA but its pass is ignored. Only
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

## Landing failures

`lines.sh ledger check <slug> <id> <sha>` and `parallel.sh scope <slug> <id>
<sha>` show where a line stands before `land` (`NOT-PASSED` means verify
first); `land` runs both itself, plus the current attempt's receipt.

- `parallel.sh land <slug> <id> <sha>`: lands `base..<sha>` uncommitted
  in the main tree. It refuses when the line's branch head is no longer
  that SHA: the branch changed after verification. Log it; the branch's
  new head is a new delivery that needs its own pass (a new attempt when
  the worker kept writing after its receipt).
- Run the line's checks, every finished stage's conditions, and the
  protected checks in the main tree, without leaving files behind
  (`PYTHONDONTWRITEBYTECODE=1` for Python, output directories outside the
  repo): an untracked file in the main tree makes the next `land` refuse.
  An untracked file these checks did produce: list it, then delete it.
  One they did not produce goes to the user first, per **Ask first** in
  `SKILL.md`.
- `land` itself refused or hit a conflict: nothing landed, so never
  unland (the tree may hold the user's changes); fix the cause. One
  exception: `could not record <marker>` means the code did land but
  unland cannot undo it; do not land again, check the files it lists
  against the source SHA, and restore them by hand. A failure
  after `land` succeeded (the checks above, or the commit): `parallel.sh unland <slug> <id>` (it undoes only the
  files that land recorded, and refuses once the land is committed), then
  a fix attempt as in **Ledger**.
- `landed` refused after the commit because the table or the log could not
  be written: the record stays; fix the cause and run `landed` again (it
  is safe to repeat), never set `state=landed` by hand.

`parallel.sh cleanup <slug>` removes only lines in state `landed`, `done`,
`dead`, `stopped`, or `planned` (never dispatched); it keeps and lists
`dispatched`, `stop-unconfirmed`, any other state, and a landed line whose
branch has commits past what landed. Its ignored and untracked file rules
are those of `references/parallel.md`.

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
4. Go on from **Collect** (`playbooks/lines.md` step 4).
