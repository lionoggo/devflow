# Delegation

Default to doing the work directly. Delegate only when the environment's
delegation policy allows it and the split is bounded, independently checkable,
and lowers total cost. Task size alone is not a reason.

- Read-only workers (noisy search, risk review) are the cheap, common case.
- Writing workers need satisfied dependencies, stable interfaces, and disjoint
  write scopes. Public interfaces, manifests, lockfiles, and final glue code
  stay with the owner unless a disjoint scope is proven.
- Run tests only after relevant writers stop.

## Worker Prompt

```text
Implement <bounded goal> from <plan/spec/brief>.
Supports: <acceptance labels>
Already satisfied: <dependencies or none>
Write scope: <paths/modules, or read-only>
Done when: <observable evidence>

Stay inside the write scope; stop and report if the task needs to cross it.
Do not revert others' changes or spawn nested workers. Do not add permanent
tests unless this prompt names the regression they protect. Run checks for
your slice. Report changed files, supported labels, check results, and risks.
```

## Failure and Integration

- Inspect the actual workspace and diff, not only the worker's message.
- Do not reassign a write scope until the previous writer has stopped. Take
  over, narrow, or retry with a corrected prompt; never auto-revert user work.
- After workers finish: review the combined diff and test changes as one set,
  remove duplicate tests and helpers, run final checks, and reconcile every
  acceptance label. Worker output is not accepted until reviewed.
