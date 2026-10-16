# 并行实施 (parallel)

**Several independent units built at once, each by a background subagent in
its own worktree; you coordinate, land each unit as one commit, and run the
full checks.** A local take on pstack `autopilot-stack` with the throughput
checkpoint from `feature`. Principles: 小步可验证, 真实证据, 先减后加. `$S` is
this skill's directory.

## Throughput check (always, before writing code in 实施 or at an unattended frame)

Write four items:
1. **First steps**: interfaces, types, shared config other units depend on.
   They go first, in order, as normal units.
2. **Independent units**: each with the globs it writes, pairwise disjoint,
   not depending on each other's unlanded code.
3. **Shared files**: anything two units would both edit (README, registries,
   `__init__`, a shared test entry). Take them out of the units; you edit them
   after every unit lands.
4. **Verdict**: "并行：可拆 N 路（单元 …），预计多花约 X、墙钟约省 Y（暂定估算）。说"并行"即可启用", or "并行：不适合，<原因>".

Suggest it only with at least two independent units, each over about 50
changed lines or a check over about 2 minutes (provisional thresholds).
Without the user's "并行" (or "开始，并行" at an unattended frame), carry on
in order without waiting. The user's word is the explicit request for
worktrees; it covers only what `parallel.sh` and the worktree subagents
create and remove. In Codex the steps are the same with the tools in
`references/hosts.md`; the differences are marked "Codex" below.

## Run

1. `$S/scripts/parallel.sh prepare <slug>` (needs a clean tree: with the
   user's uncommitted changes present, list them, say parallel needs a clean
   tree, and work in order). Worktrees sit inside the repo at
   `.claude/worktrees/` (Codex: `.dflow/worktrees/`), and lint and test runners that read only
   `.gitignore` will scan them: check that each check command skips it (as
   for `.dflow/` in the frame) before dispatch. Fill `.dflow/<slug>.units.tsv`: `id deps paths
   state base agent branch dispatched_at tries landed`; you are its only
   writer. Then `parallel.sh overlap <slug>`; fix the split until it passes.
2. **Dispatch** every ready unit (its deps landed): write its brief from
   `references/unit-brief.md`, set `base` to the current HEAD, `state
   dispatched`, `dispatched_at`, then start background subagents in one
   message: Agent with `isolation: "worktree"`, `run_in_background: true`,
   model `sonnet`. Codex: per unit, `parallel.sh worktree <slug> <id>`, set
   `branch` to the branch it prints, then `spawn_agent` (`fork_context:
   false`) with the brief, its 准备 line replaced by "工作目录 <path>：每条命令都在这里运行，只在这里提交";
   record the agent id. At most 3 running; refill as each finishes. Past about 70%
   of an unattended deadline, dispatch nothing new.
3. **On each completion** (one at a time; any wake-up in an unattended run is
   a Round, so `run-state.sh check` comes first; Codex: `wait_agent` on the
   running ids returns them):
   1. Read the report; record `agent` and `branch`. Append its decision rows
      to the run's decision log with phase = unit id and `agent-<id>` in the
      evidence.
   2. `parallel.sh scope <slug> <id>`: ancestor check and path check. A
      failure sends the unit back.
   3. `parallel.sh land <slug> <id>`: the unit's changes, uncommitted, in the
      main tree. A conflict aborts cleanly and sends the unit back.
   4. In the main tree run the unit's checks, every finished stage's
      conditions, and the protected checks. Pass: `git add` only the unit's
      paths, commit once, set `landed <sha>`, log it. Fail:
      `parallel.sh unland <slug> <id>`, send the unit back.
   5. Sent back: `tries`+1, a fresh subagent from the new HEAD with the reason
      in its brief. Never resume the old one for a sent-back unit. A worker
      that stopped because of a usage limit or an API error (not its work)
      is not sent back: after the limit resets, resume that same agent with
      SendMessage (Codex: `send_input`) (its worktree keeps the progress), no
      try counted. A second failure: do it
      yourself in order (edit and commit in one step; completions that
      arrive meanwhile wait), or mark it dead.
   6. No completion after twice the brief's time box: treat it as in a
      pickup (below) and count a try.
4. **Shared files** after every unit landed, as a normal unit.
5. `parallel.sh cleanup <slug>` (Codex: `close_agent` each worker first): removes landed (and empty) units' worktrees
   and branches, listing any untracked files it deletes; keeps and lists
   units with unlanded commits or uncommitted tracked changes; never touches
   worktrees outside the table.
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

For each `dispatched` unit: its branch has commits past `base` → handle as a
completion (step 3); no branch or no commits → dispatch again; a worktree
with uncommitted changes → keep it, list the files, never delete.
