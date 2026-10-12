---
name: devflow-commit
description: "Prepare or create safe local Git commits from existing workspace changes, including exact scope selection, atomic commit splitting, selective staging, commit-message generation, and post-commit checks. Use when the user asks to commit current changes, prepare a commit, split changes into commits, commit only specified or current-session work, or inspect commit readiness. Do not use to implement or repair code, or to push or create an MR/PR."
---

# Devflow Commit

- Already-staged changes are the user's choice: commit them as their own
  commit first (or ask); never mix unstaged changes into that commit, and
  never unstage or reset the index.
- If a merge or rebase is in progress, say so. When its conflicts are resolved
  and the user asked to commit, complete it as a merge commit and tell the
  user it was a merge; otherwise stop and report.
- If a hook only fixes formatting and asks to re-stage, re-stage only the
  hook's changes and commit again; if they can't be separated from the user's
  unstaged changes, or the hook fails for another reason, stop and report.
  Never `--no-verify`, amend, rewrite history, or push.

Reply with the commits made (`sha subject`, one per line) and anything left
uncommitted with the reason.
