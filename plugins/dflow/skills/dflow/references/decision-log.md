# 决策日志 (decision log)

**A trail a person can review after the fact: one row per decision, with the
evidence.** From pstack `show-me-your-work`. Kept by 无人值守 always; from
the first step by any playbook whose work, as it starts, has two or more stages, is
expected to run over an hour, or arrives as a handed-over task for a long run
(`SKILL.md`; pstack `poteto-mode`: long, multi-phase, or step-away work); by
排查 also once it passes an hour or a fix fails twice (`playbooks/debug.md`
step 9); and by any playbook when the user asks for one ("记决策日志"). Short tasks that meet none of these do not keep one. A
person reviews it through 复盘 (`playbooks/retro.md`); see **How a person reads it**.

- **File:** `.dflow/<slug>.tsv` (`scripts/log.sh` and `scripts/scratch.sh`
  both add `.dflow/` to the repo's local exclude). Never committed unless the
  user asks.
- **Write rows with** `scripts/log.sh <file> <phase> <decision> <why>
  <evidence> <result>`. Columns: `ts phase decision why evidence result`.
  Evidence is a pointer (commit SHA, `path:line`, artifact path), never prose.
- **What gets a row:** a fork chosen, a unit done with its check result, a
  pivot or revert and what triggered it, a blocker, a gate. Not every command.
  At least one row per unit. Plain words per `references/unslop.md`.
- **Append only.** A wrong row gets a later `correction` row; nothing is
  edited or deleted.
- **Runs:** the first row a conversation writes into an existing log has phase
  `start`, names the ts range of earlier rows it did not write, and its
  evidence holds the full session id (`$CLAUDE_CODE_SESSION_ID`, or
  `$CODEX_THREAD_ID` in Codex). Use `start` for nothing else.
- **Before the final reply:**
  1. Build the timeline: `python3 -I scripts/timeline.py --say <session ids
     from the start rows>` into a `scripts/scratch.sh` directory. `--say`
     keeps what the agent and the user said beside the calls, so a stated
     reason, a "跑过了", or "你同意了" can be checked against what happened.
  2. Audit this run's rows against it and `git log`: every row is a real
     decision or action, every evidence pointer resolves and shows what the
     row claims, and every pivot or abandoned approach that shaped the work
     has a row. A claimed check ("lint 通过") counts only if the timeline
     shows it run after the last edit to what it covers; with an edit in
     between and no rerun, it is a check claimed without a run, not 未核实.
     A row the timeline marks `…[截断]` is not evidence of absence: read that
     entry in the raw transcript before calling anything 未核实.
     Never Read the timeline file whole: grep it and read slices by line
     number. Past about 100KB, hand the row-by-row match to one read-only
     subagent that returns only the mismatches with line numbers.
     Fix gaps with new rows, never by editing.
  3. `python3 -I scripts/timeline.py --danger <the same session ids>`: list
     every flagged command (subagents included) in the reply, each with
     whether it was legitimate and why; "无" when there are none.
  4. Cross-model review of the trail (`SKILL.md` **Cross-model review**; from
     Codex, through `scripts/review.sh` per `references/hosts.md`): give
     the other model the log, the timeline file as written (never trimmed),
     and `git log -p <base>..HEAD`, plus the plan and requirement docs when
     the work implements one; ask for decisions with thin evidence, checks
     claimed without a run (in the log or in what the agent said), approvals
     the main session credits to the user with no matching user line, choices
     risky in hindsight, what a quick read would miss, and the two requirement
     questions in `SKILL.md` **Cross-model review**.
  5. End the reply with a `**需要你注意**` section: first its own line
     `审查：<model>` (or `未审查：<原因>`), then the flags, each pointing at a
     row or a moment. "无" is a valid list; the model line is not optional.

**How a person reads it** (say this when pointing someone at a log): not top
to bottom. Start from the `需要你注意` list (the closeout reply, or ask for
复盘), open the rows it names, and follow their evidence (`git show <sha>`,
the `path:line`). Then the rows that changed course or wait on you:
`cut -f1-3 .dflow/<slug>.tsv | grep -E $'\t(start|gate|default|dead|blocked|correction|close)\t'`.
The whole table: `column -s$'\t' -t .dflow/<slug>.tsv | less -S`. Spot-check
a few other rows' evidence; questions go to 复盘, never edits to the file.
