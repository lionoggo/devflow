# Handoff

Use when work should start or continue in another session or workspace:
implementation, or an investigation, evaluation, research, or design task,
including a mid-task handoff. The default remains the current workspace.

## Choose the Carrier

- Plan just approved, nothing implemented yet: prefer a plan file
  (`docs/plan-<topic>.md`) plus a one-line prompt that points to it.
- Work in progress: a full receiver prompt with the Progress section below.
- Save the prompt to a file when the user asks or it is long; report the path.

## Choose the Target

- Keep the current workspace when it is safe and isolation adds nothing.
- Use another existing or new workspace only when it protects unrelated dirty
  work, avoids an unsuitable branch, or repository rules require it, and the
  user has authorized creating or switching workspaces.
- Before sending, know the target's branch/HEAD, dirty state, required setup,
  and that the plan is inline or readable there. Never stash, commit, copy,
  or discard work to make a target fit; report a blocker instead.

## Deliver

- `prompt-only`: return the receiver prompt below; nothing else happens.
- `launch`: when the user authorized it, deliver through the launcher they
  chose, following that tool's own skill or docs (for Orca, `orca-cli`).
  Stop your own writes first. On a timeout or ambiguous result, inspect the
  launcher's state; never resend until non-delivery is confirmed. Ownership
  moves only after delivery is confirmed; then report the target and stop.
  Prompt delivery is not implementation progress.

On failure report where it failed, what residue exists, and who owns writes
now. Do not delete partial resources automatically.

## Receiver Prompt

```text
You own <implementation of the approved scope | investigation of <problem> |
evaluation | research | design of <topic>> in <absolute repo path>.

Read first: <instructions files>, <plan/spec/brief/notes>, <key files>
Goal: <one paragraph>
Non-goals: <out of scope>
User principles: <principles and preferences the user set in the discussion,
in their words where short>
Decisions: <selected choices>; open decisions: <none, or who decides>
Done when: <A1..An with verification methods, or the question to answer and
the evidence it needs>
Target: <workspace, branch/HEAD, dirty/untracked files, setup>
Progress (omit when nothing is done yet):
- Done: <results with evidence>
- Remaining: <labels, steps, or open questions>
- Decisions made during work: <choices and why>
- Known issues / pitfalls: <what failed, what was ruled out, what to avoid>
Constraints: preserve unrelated changes; keep edits within <scope, or
read-only>; <architecture constraints>

First verify that branch, HEAD, and dirty files match Target; if they do not,
stop and report the difference before editing.

<implementation:> Use devflow-impl. Keep the acceptance labels; stop and
report instead of deciding open product or architecture questions or weakening
acceptance. Finish with the devflow-impl closeout.
<other tasks:> Use <the fitting skill, e.g. devflow-debug or devflow-research>.
Report findings with evidence; do not start implementing unless asked.
Do not hand off again or change the workspace.
```

Keep only the task line and closing lines that fit; drop empty fields.

Leave out transcripts, dead ends, raw logs, credentials, and unrelated
ignored-file contents.
