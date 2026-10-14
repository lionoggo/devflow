# 决策日志 (decision log)

**A trail a person can review after the fact: one row per decision, with the
evidence.** From pstack `show-me-your-work`. Used by 无人值守 always, and by
any attended work with two or more stages or expected to run over an hour
(实施 of a staged plan, a long 排查). Short tasks do not keep one.

- **File:** `.dflow/<slug>.tsv` (`.dflow/` stays out of Git via
  `scripts/scratch.sh`'s exclude line). Never committed unless the user asks.
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
  evidence holds the full `$CLAUDE_CODE_SESSION_ID`. Use `start` for nothing
  else.
- **Before the final reply:**
  1. Build the timeline: `python3 -I scripts/timeline.py <session ids from the
     start rows>` into a `scripts/scratch.sh` directory.
  2. Audit this run's rows against it and `git log`: every row is a real
     decision or action, every evidence pointer resolves and shows what the
     row claims, and every pivot or abandoned approach that shaped the work
     has a row. Fix gaps with new rows, never by editing.
  3. `python3 -I scripts/timeline.py --danger <the same session ids>`: list
     every flagged command (subagents included) in the reply, each with
     whether it was legitimate and why; "无" when there are none.
  4. Cross-model review of the trail (`SKILL.md` **Cross-model review**): give
     the other model the log, the timeline file as written (never trimmed),
     and `git log -p <base>..HEAD`; ask
     for decisions with thin evidence, checks claimed without a run, choices
     risky in hindsight, and what a quick read would miss.
  5. End the reply with `**需要你注意**（审查：<model> / 未审查：<原因>）` and
     its flags, each pointing at a row or a moment. "无" is a valid list.
