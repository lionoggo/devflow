---
name: devflow-autorun
description: "Arm, resume, close, or report the progress of unattended long runs: a written contract with command-checkable done conditions, one local branch, a structural guard, and an append-only decision log. Only for explicit /devflow-autorun."
disable-model-invocation: true
---

# Devflow Autorun

Prepare work that runs while the user is away, and resume or close it later.
The user grants authority only here, when arming. Each iteration runs in
`devflow-autorun-tick`. Paths: `S=~/.agents/skills/devflow-autorun/scripts`,
and run files sit in `<repo>/.devflow/<slug>.{md,tsv,running}`.

## Arm (the user is present)

1. Draft `.devflow/<slug>.md` from `references/contract.md`. With an approved
   plan, take the contract's row from the plan's 契约拆分 table (write scope,
   done-condition commands, budget). Do not copy the plan's 人工项 table; the
   closeout hands those to the user from the plan. Without a plan, propose defaults for the user to edit:
   done = the project's test command passes, write scope = the source directory.
   Every done condition is a command with an expected result. Checks that need a
   human (UI look, real external service) and the plan does not already list go
   under 人工项 and never count toward done. A question only the user can
   answer is not a 人工项: the run parks it.
2. Refuse to arm, and say why, unless all of these hold:
   - The worktree is clean outside `.devflow/`. Or the contract names a worktree
     path and the user asked for it to be created with their usual tool (`wt`,
     `orca-cli`, `git worktree`). Never create, switch, or delete one without that.
   - The contract authorizes local commits to its own branch (`autorun/<slug>`
     by default); `arm.sh` creates or switches to it on go.
   - Each done condition runs, and fails now; record the output under `基线`.
     If one already passes, the contract says why. Ask whether a cheaper
     implementation that breaks the intent could still pass
     (`devflow-plan/references/plan.md` claim strength). If one could, add the
     condition that tells them apart.
3. Protected paths are the tests, fixtures, and scripts that the done
   conditions run, plus any the user adds. Write scope is the smallest set of
   path prefixes or globs that the work needs. A path never sits in both.
4. Show one screen, not the whole contract: the done conditions (one line each),
   what may change and what is protected, the time budget, the baseline, the
   number of 人工项, and the contract path. Stop. Wait for the user's explicit go.
   For the first run of a new kind of task, suggest the user watches the first iterations.
5. On go:
   - Run `$S/arm.sh <root> <slug>`. It checks the contract fields and the
     worktree, prepares the branch, writes the marker, self-tests the guard,
     logs the start row, and keeps the Mac awake until the deadline. If it fails, report its message and stop; fix the contract with
     the user and ask for go again. Never write the marker or the start row by hand.
   - Prove the guard is live in this session: run `git tag --list`. The guard
     must block it. If it runs, `rm` the marker that `arm.sh` printed and refuse to arm.
   - Start the loop: call the Skill tool with `loop` and the args
     `/devflow-autorun-tick <slug>` (no interval). If that is not available,
     tell the user to type `/loop /devflow-autorun-tick <slug>`.
   - Tell the user that a notification comes when a unit is parked or the run
     closes, that "/devflow-autorun 进展" reports where it is, and that the run needs a permission mode that
     will not stop for prompts; the guard is what makes that acceptable.
     Commits, pushes, and publishing outside this run keep their usual rules.

## Resume (a new session)

Read the contract, the marker, and the log tail. Run `$S/check.sh <root> <slug>`
and show the result. Treat logged decisions as given. Rerun the done
conditions instead of trusting a logged pass. On the user's go:
- rebind the marker's `session_id` to this session with `jq`, and record a fresh
  `contract_sha256` if the user edited the contract and has now seen it;
- log a `start` row naming the `ts` range this session inherits;
- start the same loop as in Arm.

If check fails, stop and report. Never clean up to make it pass.

## Progress

`/devflow-autorun 进展` (or "进展", "status", "做到哪了"): read-only. For each
`.devflow/*.md` contract, read its `目标`, whether its marker exists, and the
tail of its log. Answer in a few plain lines: what is running and its latest
step, each recent run's result (the latest `close` row), and what waits for the
user (`parked:` rows of each contract's latest run). No IDs, hashes, or paths
unless asked.

## Abort

The user stops the loop (Esc, or the loop's stop) and removes the marker. The
branch and its commits stay. Report what landed using the log and
`git log <base>..HEAD`.

## Guard

`$S/guard.sh` is a global Claude Code PreToolUse hook. It acts only on the
session named in a live marker. It blocks:
- push, pull, merge, rebase, reset, stash, clean, checkout/switch, tag, worktree,
  and branch changes;
- publishing and `gh` remote actions;
- amend, `--no-verify`, `-a`, and compound commits;
- commits that stage protected or out-of-scope files, or that run off the contract branch;
- writes outside the write scope, to protected paths, or under `.devflow/`;
- edits to the marker.

It allows `git restore` on in-scope paths from HEAD. After the deadline it
allows only closeout. The guard fails open: if it errors or times out, the call
goes through. That is why `check.sh` verifies the state independently. It
checks the contract hash, protected and out-of-scope changes from any tool,
commits since the base, the branch, and the deadline. `$S/guard-test.sh` and
`$S/check-test.sh` are the regression tests. Run both after editing either script.
