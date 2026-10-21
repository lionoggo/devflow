---
name: devflow-autorun-tick
description: "Iteration step of an armed devflow-autorun run, entered from /loop /devflow-autorun-tick <slug>. Does nothing unless a run marker for this session exists. Not for ordinary tasks."
---

# Devflow Autorun Tick

`S=~/.agents/skills/devflow-autorun/scripts`. Argument: `<slug>`. Run files
are in `<repo>/.devflow/`.

## 0. Gate

Read `.devflow/<slug>.running` with the Read tool or a single plain `jq`/`cat`
(the guard blocks any other command, including log text, that names the marker
file). If it is missing, or its `session_id` is not
`$CLAUDE_CODE_SESSION_ID`, reply "无活动运行" and stop. In `/loop` dynamic mode,
also end the loop. Change nothing.

## 1. Each iteration

1. Reread `.devflow/<slug>.md` and the last 15 rows of `.devflow/<slug>.tsv`.
   Context may have been compacted, so trust these files over memory. Read
   `~/.agents/skills/devflow-impl/SKILL.md` once per session for plan discipline.
2. Run `$S/check.sh <root> <slug>`. Any problem stops the run at once (go to
   step 3). Do not repair, revert, or clean anything the run did not just write.
3. Pick the smallest next unit, the riskiest unknown first. State its hypothesis.
4. Edit inside the write scope. Run the unit's check, then every done condition.
5. Before calling it progress, run `$S/check.sh <root> <slug>` again. A problem
   stops the run. It advanced when a condition moved toward passing and none
   regressed. Then:
   - `git add <paths>`, then commit separately with `git commit -m "<type>(<scope>): <subject>"`;
   - log it with `$S/log.sh .devflow/<slug>.tsv <label> "<what>" "<why>" "commit <sha>; <check output pointer>" "<conditions state>"`.

   Otherwise:
   - `git restore <paths>` for its edits, and `rm` the files it created;
   - log why and the pivot.

   The `commit <sha>` evidence format is what `check.sh` reads.
6. If a unit needs a protected path, or a product or architecture decision that
   only the user can make, park it. Log it with result `parked: <reason>` and
   continue with independent units. Never work around the guard. A guard block
   is logged and parks the unit.

7. Notify at two moments only, once each, with PushNotification (load it with
   ToolSearch if it is deferred): right after logging a `parked:` row
   ("等你决定 <slug>/D<n>：<reason in a few words>"), and after closeout removes
   the marker ("<slug> <完成|部分完成|受阻>", plus how many items wait for the
   user). When one tick does both, send one message. Do not retry a
   notification that was not sent, and do not log notification results.

Log decision points, not every command.

## 2. Stop when

- every done condition passes, which leads to closeout;
- the deadline or the contract's iteration cap is reached;
- a dead end: 3 iterations in a row without progress after at least one pivot;
- every remaining unit is parked;
- `check.sh` reports a problem, or anything moved under the run.

Never relax or reinterpret a done condition to reach a stop.

## 3. Closeout

1. Run `$S/check.sh <root> <slug> closeout`. Any uncommitted change outside
   `.devflow/` stops closeout as 受阻. Report it and never clean it. Then rerun
   every done condition on this committed state and record the real output.
2. Check the log against `git log <base>..HEAD`. Every advance row maps to a
   real commit. Fix mistakes with a new row, never by editing.
3. Log a `close` row whose decision column is exactly one of 完成 / 部分完成 /
   受阻; put the explanation in the other columns. Then
   `rm .devflow/<slug>.running`, notify (§1 step 7), and end the loop.
4. Reply in the devflow-impl closeout shape:
   - result (完成 / 部分完成 / 受阻) and the commit range `<base>..HEAD`;
   - each condition → evidence → result;
   - parked units and dead-end notes;
   - 人工项 from the contract and the plan's 人工项 table as a checklist for the user;
   - the log path.
5. Suggest independent acceptance in a new session with `devflow-verify`, given
   only the contract's conditions, the commit range, and the log
   (`devflow-impl/references/handoff.md`).
