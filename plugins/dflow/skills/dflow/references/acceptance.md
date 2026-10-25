# Acceptance Matrix

Use for inherited plans or several criteria where a compact table keeps the
result traceable.

```text
Label | source (user request / plan result or constraint) | observable result |
verification method | evidence | result
```

## Rules

- Required criteria are limited to: results the user currently asked for,
  constraints the user or plan requires, and mechanisms without which those
  cannot be proven. Stage results and checks are evidence, not criteria,
  unless the result cannot be proven without them.
- Every plan result and required constraint maps to at least one criterion.
  An uncovered item, or one the implementation dropped, is reported as
  `needs decision`, not skipped.
- A changed implementation method is fine when the promised result and
  constraints still hold.
- A new criterion states whether it comes from newer user intent or is needed
  to prove an existing result. For a new technical observation, keep it as a
  note if it can fail while the user result still completes safely.
- A criterion is invalid only when based on a disproven fact, unverifiable as
  written, or superseded by newer user intent; and even then the user
  decides. Missing implementation, hard or expensive verification, or an
  unavailable environment does not make a criterion invalid.
- One evidence source may cover several criteria. Logs support evidence but
  should not be the only basis when the product result can be observed.
- Stage evidence may be reused when current and trustworthy.

## Repair Loop Notes

- Before each repair: the user goal is unchanged, the criterion still holds,
  and the failure is reproducible or well evidenced.
- Repair happens only where `playbooks/verify.md` step 7 grants it; then
  the session that built the candidate is the only writer. An independent
  verifier and any helper subagents stay read-only. When delegating investigation, pass raw failure evidence, not a
  repair guess.
- Count rounds only for the same product defect under stable criteria;
  harness fixes, environment retries, and goal changes do not count.
