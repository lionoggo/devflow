---
name: devflow-verify
description: "Verify an implemented change against the user-visible outcome: set or inherit acceptance criteria, observe real evidence, classify failures, and repair confirmed defects when asked. Use when the user asks to verify, 验收, accept, browser-test, run end-to-end checks, validate a diff/commit/feature, or repair until accepted. Do not use to diagnose a reported failure when no change is under test (devflow-debug)."
---

# Devflow Verify

Establish, with observed evidence, whether the current implementation meets
the requested outcome.

## Invariants

These hold at every size of change:

1. Criteria come from confirmed intent; criteria derived after the fact are
   labeled as derived.
2. Evidence is at the level of the claim: a user-visible or runnable result
   needs an observation on the real usage path; unit, static, and mocked-platform
   checks (fake browser, fake API, fake device) only support it.
3. A whole-feature verdict needs whole-feature evidence on the final
   integrated state; what cannot be observed is reported, never assumed.

## Who Verifies

Pick by situation; the user can always choose directly.

- Small change (copy, style, single config): show the diff and one real output
  (or point the user to what to look at); the user's confirmation is valid
  evidence, and until they confirm the verdict is 部分通过. Skip the full process.
- Regular feature: verify in this session, judging only from freshly observed
  evidence, not from reasoning made while implementing.
- Cross-module or high-risk (user-facing alone is not enough), when subagents
  are available: delegate to a read-only verifier subagent given only the
  criteria and the candidate (workspace, diff or commit), not the
  implementation reasoning; then check its evidence yourself.
- Long context, cross-session handoff, or on request: a new session via a
  handoff prompt carrying the criteria and the candidate.

## Mode

- `verify-only` (default): do not edit code, tests, fixtures, or Git state.
- `verify-and-repair`: when the user asks to fix what fails or close the
  loop. Repair only defects whose cause and bounded scope are established;
  otherwise report what evidence or decision is needed. The repairing session
  is the only writer.

## Criteria

Take criteria from the latest user request first, then an approved plan's
acceptance (keep its labels, including E-items), then a debug diagnosis. Code
and closeout reports are evidence of what was built, never authority to lower
the expected result. Without a plan, derive a few criteria from the user's
own words (never from what the implementation happens to do), list them
marked "derived" with their basis, and proceed. When the user's words leave a
meaning open that the implementation silently chose (units, semantics such as
"打折" = percent off vs. amount off, boundaries), that is an ambiguity that
changes pass/fail: ask once before judging. Do not widen
acceptance with an old plan after the user narrowed the goal, and never drop
or weaken an approved criterion silently — that needs a user decision.

## Process

1. Pin the candidate: workspace, diff or commit, and the observable result.
2. For each criterion, run the cheapest evidence at the level it needs. Prefer
   existing checks and real product paths. Evidence that touches shared or
   external state (production data, real messages or payments, deploys,
   dependency installs) needs the user's confirmation first, unless they
   explicitly authorized that specific action.
3. Run E-items last, on the final integrated state (fresh build, real
   configuration). If an E-item cannot be observed, report it as not observed;
   when it needs a human (UI, real external service), give the user a short
   manual checklist instead of claiming a result.
4. Classify each failure: `product-defect`, `harness` (test/fixture/driver
   problem), `environment`, or `baseline` (already failing before the change).
5. In `verify-and-repair`, fix a confirmed in-scope product defect with the
   smallest change, then rerun the affected evidence and relevant regression
   checks. Fix `harness` only in existing maintained test surfaces. Preserve
   unrelated dirty work. Stop after three rounds on the same defect, or when a
   repair needs an architecture or public-contract change, and report.

For multi-criterion or inherited acceptance, see `references/acceptance.md`.

## Evidence Rules

- No observed evidence, no pass. A required path left unobserved is not a pass.
- For a critical constraint, the evidence must distinguish a correct
  implementation from a cheaper one that violates it while looking the same.
- A failure with no proven effect on the expected result is a note, not a
  defect.
- Keep the amount of evidence proportional to the change's risk; run broad
  sweeps (exhaustive comparisons, strict type checks, full suites beyond the
  affected area) only when a key risk needs them.
- A permanent new test only for a credible, stable regression not already
  covered; otherwise use existing evidence or a temporary uncommitted script.

Never stage, commit, push, merge, rebase, or amend from this skill. To compare
with a baseline, read old versions with `git show <rev>:<path>` or export them
to a temporary directory; never use checkout, reset, stash, or clean on the
working tree.

## Output

Write for the user: conclusion first, plain headings in the reply language, no
internal status codes or English field names; omit empty items. The headings
below show the shape, not fixed text.

```text
**验收结论**：<通过 / 未通过 / 部分通过 / 无法完成验收> — <one sentence>
  通过 = every required criterion observed at its level, including the real usage path of user-visible claims
  未通过 = any required criterion was observed failing, even if others passed
  部分通过 = nothing observed failed, but some required items could not be observed, e.g. 测试都过了，但页面上的效果还需要你打开看一下
  无法完成验收 = nothing required could be observed
- 标准与证据：<one line per criterion: criterion → how it was checked (level) → result; mark derived criteria>
- 问题：<confirmed defects and repairs made>
- 未覆盖：<items not observed, manual checklist for the user, environment or baseline gaps>
```

Optional observations go under 未覆盖 or 问题, never into the verdict. When a
real usage path was not observed, give the manual checklist.
