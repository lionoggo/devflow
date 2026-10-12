# Plan Shape

Use the smallest plan that preserves the decision. In chat, write field names
in the reply language and drop lines whose value is none. The same shape is consumed
by `devflow-impl` and `devflow-verify`, so keep its acceptance criteria stable.

## Core Plan (always)

```text
Goal: <user-visible result>
Non-goals: <excluded behavior>
Decisions: <selected choices that shape behavior, architecture, data, or scope>
Open decisions: none
Acceptance:
- A1: <observable pass condition> — verify with <method>
- A2: ...
- E1: <start → user actions → visible result> (environment)   # only when needed
Scope: <modules/boundaries touched>
Risks: <only ones that still hold after the plan>
```

- `Open decisions` must be `none` before the plan is ready. "A or B", "as
  needed", or "decide later" is open when the choice changes behavior, scope,
  ownership, data meaning, or acceptance. A recommendation is not a decision
  until the user selects it.
- Scale the form to the change: a small change needs one or two sentences
  ("how we know it works, where to look"), no labels; a regular feature uses
  A-labels; add E-items only for a cross-module or user-facing flow (otherwise
  one line saying why end-to-end does not apply).
- Every goal maps to at least one acceptance criterion traceable to the
  confirmed requirements, and each criterion names a feasible verification
  method. Files changed or tests written are not results.
- Evidence must be at the level of the claim: a user-visible or runnable result
  needs at least one check on the real usage path (real call, request, page,
  or command). Unit and static checks support it; they do not prove it alone.
- Add stages only when ordering, integration risk, or irreversibility matters.
  Each stage states what works after it and how that is checked.

## Architecture Section (only when needed)

Add it when the change crosses module or process boundaries, changes
authoritative state or ownership, introduces a public/runtime contract, or
restructures a subsystem. Anchor names in current code:

```text
Components: <component> owns <responsibility>; must not own <boundary>
Contracts: <interface/schema/event> — owner -> consumer; errors, compatibility
Dependency direction: allowed <A -> B>; forbidden <B -> A>
Runtime flow: <entry -> components -> observable result>; failure/recovery
State: source of truth, derived/persisted state, concurrency, restart
Invariants: <conditions that must stay true> — each checked by some acceptance
Change map: reuse / modify / add / remove
```

Otherwise leave it out entirely (no "architecture impact: none" line). If the
implementer would still have to decide where logic lives or who owns state,
the section is required.

## Readiness Questions

Check these before calling a plan ready; mention only the ones that fail:

1. **Closure** — does every promised result have a chain from cause/mechanism
   to observable evidence, with no required part moved into non-goals or risks?
2. **Vertical slice** — is there one smallest end-to-end path that works first?
   Is every extra backend, mode, adapter, or reusable API justified by a
   current need rather than symmetry or future reuse?
3. **Owners** — does every new or changed boundary have a real owner, entry
   point, contract, and failure behavior in live code? A filename or phrase is
   not an owner; claimed reuse must be checked against the current contract.
4. **Claim strength** — does the evidence prove the strongest claim? Startup
   proves boot, file existence proves materialization, not consumption. For a
   critical invariant, could a cheaper violating implementation still pass?
   If so, add the cheapest distinguishing evidence.
5. **Integration** — would completing every stage produce one runnable result,
   not disconnected parts? Cross-module or user-facing work turns its
   end-to-end path into E-items run on the final integrated state.

## Evidence Preference

First decide the level each claim needs (unit, integration, real usage path),
then pick the cheapest evidence at that level: reuse an existing check; extend
one existing scenario; a temporary uncommitted script; a new permanent test
only for a named, credible long-term regression that existing evidence cannot
cover. One evidence source may cover several criteria. For small changes, the
user looking at the result counts as evidence.
