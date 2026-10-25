# 并行实施 (parallel)

**Several independent units built at once, each by a background subagent in
its own worktree; you coordinate, land each unit as one commit, and run the
full checks.** A local take on pstack `autopilot-stack` with the throughput
checkpoint from `feature`. Principles: 小步可验证, 真实证据, 先减后加. `$S` is
this skill's directory.

并行 is the inside of one 实施: units of one plan, on same-host subagents.
多线 (`playbooks/lines.md`) is the session-owned program across models,
sessions, and windows; it reuses this file's unit table (with six more
columns, which this file ignores) and its landing steps.

## Throughput check (always, before writing code in 实施 or at an unattended frame)

Write four items:
1. **First steps**: interfaces, types, shared config other units depend on.
   They go first, in order, as normal units.
2. **Independent units**: each with the globs it writes, pairwise disjoint,
   not depending on each other's unlanded code, and each still working and
   verifiable when landed alone. Disjoint files are not enough: work coupled
   at run time (one state machine, an animation and its controller) is one
   unit, or its shared contract goes first.
3. **Shared files**: anything two units would both edit (README, registries,
   `__init__`, a shared test entry). Take them out of the units; you edit them
   after every unit lands.
4. **Verdict**: "并行：可拆 N 路（单元 …），预计多花约 X、墙钟约省 Y（暂定估算）。说"并行"即同意为这 N 个单元各建一个 worktree，落地后删除", or "并行：不适合，<原因>".

Suggest it only with at least two independent units, each over about 50
changed lines or a check over about 2 minutes (provisional thresholds).
Without the user's "并行" (or "开始，并行" at an unattended frame), carry on
in order without waiting. The user's "并行" is the explicit request for
worktrees: it meets any rule (a global AGENTS.md included) that asks for the
user's explicit word before creating worktrees, for exactly what
`parallel.sh` and the worktree subagents create and remove. "On this
branch" means where the units land, not where workers run. Never run two
workers in one shared tree; when worktrees are not possible, work in
order. In Codex the steps are the same with the tools in
`references/hosts.md`; the differences are marked "Codex" below.

## Run

1. `$S/scripts/parallel.sh prepare <slug>` (needs a clean tree: with the
   user's uncommitted changes present, list them, say parallel needs a clean
   tree, and work in order). Worktrees sit inside the repo at
   `.claude/worktrees/` (Codex: `.dflow/worktrees/`), and lint and test runners that read only
   `.gitignore` will scan them: check that each check command skips it (as
   for `.dflow/` in the frame) before dispatch. Fill `.dflow/<slug>.units.tsv`: `id deps paths
   state base agent branch dispatched_at tries landed`; you are its only
   writer. `overlap` needs the manifest `.dflow/<slug>.md` with an `allow:`
   line (and `protect:`, or `protect: -` for none); an attended parallel
   run without one writes a short one first (slug, branch, base, allow,
   protect). Then `parallel.sh overlap <slug>`; fix the split until it passes.
2. **Dispatch** every ready unit (its deps landed): write its brief from
   `references/unit-brief.md`, set `base` to the current HEAD, `state
   dispatched`, `dispatched_at`, then start background subagents in one
   message: Agent with `isolation: "worktree"`, `run_in_background: true`,
   model `sonnet`. Codex: per unit, `parallel.sh worktree <slug> <id>`, set
   `branch` to the branch it prints, then `spawn_agent` (`fork_context:
   false`) with the brief, its 准备 the working-directory form in `references/unit-brief.md` (no `git switch`);
   record the agent id. At most 3 running; refill as each finishes. Past about 70%
   of an unattended deadline, dispatch nothing new.
3. **On each completion** (one at a time; any wake-up in an unattended run is
   a Round, so `run-state.sh check` comes first; Codex: `wait_agent` on the
   running ids returns them):
   1. Read the report; record `agent` and `branch`, and fix the HEAD SHA it
      reports as the unit's SHA for the next steps. Append its decision rows
      to the run's decision log with phase = unit id and `agent-<id>` in the
      evidence.
   2. `parallel.sh scope <slug> <id> <sha>`: ancestor check and path check
      on that SHA. A failure sends the unit back.
   3. `parallel.sh land <slug> <id> <sha>`: `base..<sha>`, uncommitted, in
      the main tree (it runs the scope check itself too). It refuses when the branch head is no longer that SHA
      (the branch moved after the report): the unit is not done as
      reported; read its final report again, or send it back. A conflict
      aborts cleanly and sends the unit back.
   4. In the main tree run the unit's checks, every finished stage's
      conditions, and the protected checks, leaving no files behind
      (`PYTHONDONTWRITEBYTECODE=1`, output outside the repo): an untracked
      file makes the next `land` refuse. Untracked files these checks
      produced are listed, then deleted; any other goes to the user first,
      per **Ask first** in `SKILL.md`. Pass: `git add` only the unit's
      paths, commit once, `parallel.sh landed <slug> <id>`, set `landed
      <sha>`, log it. Fail:
      `parallel.sh unland <slug> <id>`, send the unit back.
   5. Sent back: `tries`+1, `base` set to the new HEAD, a fresh subagent
      with the reason in its brief. Never resume the old one for a sent-back
      unit. Claude Code gives the new subagent a new worktree and the brief
      switches it to `base`. Codex: remove the unit's old worktree and branch
      first (after checking they hold nothing you need; `parallel.sh
      worktree` refuses an old one not at the new base), and before dispatch
      check that `git -C <path> rev-parse HEAD` equals this `base`. A worker
      that stopped because of a usage limit or an API error (not its work)
      is not sent back: after the limit resets, resume that same agent with
      SendMessage (Codex: `send_input`) (its worktree keeps the progress), no
      try counted. A second failure: do it
      yourself in order (edit and commit in one step; completions that
      arrive meanwhile wait), or mark it dead.
   6. No completion after twice the brief's time box: treat it as in a
      pickup (below) and count a try.
4. **Shared files** after every unit landed, as a normal unit.
5. `parallel.sh cleanup <slug>` (Codex: `close_agent` each worker first): removes the worktrees
   and branches of units in state `landed`, `done`, `dead`, `stopped`, or
   `planned` (never dispatched); keeps and lists units in any other state
   (`dispatched`, `stop-unconfirmed`, unknown), landed units whose branch has
   commits past what landed (the source SHA comes from `.dflow/<slug>.landed`,
   which `parallel.sh land` appends to; a unit marked landed by hand with no
   record there is kept), and units with uncommitted changes, untracked
   files, or ignored files; never touches worktrees outside the table. Set
   each finished unit's state before running it. Ignored files are listed, never removed by default. Add
   `--ignored-ok` only when every listed path is output this task's own
   commands produced (build output, caches), and name those paths in the
   reply; anything else (`.env`, samples, logs you did not write) goes to the
   user first, per **Ask first** in `SKILL.md`.
6. Close as the playbook says (影响面, decision-log audit with
   `timeline.py`, which includes subagent transcripts, codex review). Reply
   line: `并行：N 路，落地 X 个单元，退回 Y 次，保留的 worktree：…`.

## Facts this relies on (measured with Claude Code 2.1.299)

In Codex the worktree is made by `parallel.sh worktree` at the unit's base,
so there is no default-branch catch-up; Codex facts are in
`references/hosts.md`. The rest of this section is about Claude Code.

- A worktree subagent's tree is `<main repo>/.claude/worktrees/agent-<id>` on
  branch `worktree-agent-<id>`, cut from the repository's default branch tip,
  not from your current HEAD (seen from a linked worktree and from a
  `dflow/<slug>` branch alike). The brief therefore has the worker switch to
  `base` first; `scope` and `land` refuse a branch whose ancestor is not
  `base`. Command substitution (`$(...)`) in that step may be refused by the
  tool, so the brief spells out two plain commands.
- Background subagents wake the session when they finish.
- Killing the session kills its subagents. Their worktrees may vanish or stay
  behind locked and empty; a unit with commits keeps its branch.
  `parallel.sh cleanup` lists unregistered worktrees under `.claude/worktrees/`
  as ORPHAN and leaves them; name them in the reply.
- Subagent transcripts live in `~/.claude/projects/<project>/<session
  id>/subagents/agent-<id>.jsonl`.

## Pickup (a new session, unattended)

For each `dispatched` unit: its branch has commits past `base` but no final
report → not delivered: read the worker's transcript for its report; none,
then send it back (step 3.5), keeping its commits as in **Attempts and
stopping** of `playbooks/lines.md` (a `refs/dflow/` ref, then a cherry-pick
in the new brief's 准备); no branch or no commits → dispatch again; a worktree
with uncommitted changes → keep it, list the files, never delete.
