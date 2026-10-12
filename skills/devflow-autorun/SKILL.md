---
name: devflow-autorun
description: "Arm, resume, or close an unattended long run: a written contract with command-checkable done conditions, one local branch, a structural guard, and an append-only decision log. Only for explicit /devflow-autorun."
disable-model-invocation: true
---

# Devflow Autorun

Prepare work that runs while the user is away, and resume or close it later.
The user grants authority only here, when arming. Each iteration runs in
`devflow-autorun-tick`. Paths: `S=~/.agents/skills/devflow-autorun/scripts`,
and run files sit in `<repo>/.devflow/<slug>.{md,tsv,running}`.

## Arm (the user is present)

1. Draft `.devflow/<slug>.md` from `references/contract.md`, starting from the
   approved plan when there is one (keep its acceptance labels). Every done
   condition is a command with an expected result. Items that need a human
   (UI look, real external service) go under 人工项. They never count toward done.
2. Refuse to arm, and say why, unless all of these hold:
   - The worktree is clean. Or the contract names a worktree path and branch,
     and the user asked for it to be created with their usual tool (`wt`,
     `orca-cli`, `git worktree`). Never create, switch, or delete one without that.
   - The contract authorizes local commits to its own branch (`autorun/<slug>`
     by default). Create that branch from the current HEAD only after the user agrees.
   - Each done condition runs, and fails now. If it already passes, the
     contract says why. Ask whether a cheaper implementation that breaks the
     intent could still pass (`devflow-plan/references/plan.md` claim
     strength). If one could, add the condition that tells them apart.
3. Protected paths are the tests, fixtures, and scripts that the done
   conditions run, plus any the user adds. Write scope is the smallest set of
   path prefixes or globs that the work needs. A path never sits in both.
4. Show the contract, the baseline output, the write scope, and the protected
   paths. Stop. Wait for the user's explicit go. The first run of a new kind of
   task is watched, so suggest the user stays for the first iterations.
5. On go:
   - Add `.devflow/` to `$(git rev-parse --git-common-dir)/info/exclude` if missing.
   - Write the marker with `jq`. Its fields are `session_id` (`$CLAUDE_CODE_SESSION_ID`),
     `branch`, `commit_allowed`, `base_sha` (HEAD), `contract_sha256`
     (`shasum -a 256 .devflow/<slug>.md`), `write_scope`, `protected`, and
     `deadline` (epoch seconds from the contract budget).
   - Prove the guard is live: run `git tag --list`. The guard must block it. If
     it runs, the hook is not registered. Remove the marker with `rm`, and
     refuse to arm.
   - Log the arming: `$S/log.sh .devflow/<slug>.tsv start "armed" "<goal>"
     "session <id>, base <sha>" "baseline: <failing conditions>"`.
   - Tell the user to type `/loop /devflow-autorun-tick <slug>` (dynamic, no
     interval) and to keep the Mac awake (`caffeinate -i` around the CLI, or
     `caffeinate -dims` in another terminal).
   - Say that the run needs a permission mode that will not stop for prompts, and
     that the guard is what makes that acceptable. Commits, pushes, and
     publishing outside this run keep their usual rules.

## Resume (a new session)

Read the contract, the marker, and the log tail. Run `$S/check.sh <root> <slug>`
and show the result. Treat logged decisions as given. Rerun the done
conditions instead of trusting a logged pass. On the user's go:
- rebind the marker's `session_id` to this session with `jq`, and record a fresh
  `contract_sha256` if the user edited the contract and has now seen it;
- log a `start` row naming the `ts` range this session inherits;
- hand back to the same `/loop` command.

If check fails, stop and report. Never clean up to make it pass.

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
