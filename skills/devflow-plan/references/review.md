# Plan Review

Review to reduce real risk, not as a ritual. Review tries to disprove
readiness; a list of rejected bad ideas is not a review of the chosen one.

## Modes

- `self`: default. Apply the readiness questions in `plan.md` and the relevant
  lenses below.
- `subagent`: a read-only reviewer in this session, when an independent lens
  is worth its cost.
- `independent`: another session or model, when the user asks for one, the plan
  is high risk, or current reasoning may anchor a reviewer. Return the prompt
  below for manual use, or deliver it through the launcher the user selects
  (for Orca, `orca-cli`). Delivery is not a completed review; never resend
  until non-delivery is confirmed.

The planner stays the owner in every mode. Validate each finding against
current evidence, then `adopt`, `defer`, or `reject` it. Run at most two rounds;
escalate unresolved product, architecture, security, or public-contract
disagreements to the user.

## Lenses (use only relevant ones)

architecture boundaries and ownership · outcome closure · vertical slice vs.
premature generalization · compatibility and migration · security and
reliability · performance · testability (duplicate tests, heavy mocks) · user
experience

## Reviewer Prompt

```text
You are an independent read-only reviewer of the plan below. Do not edit
files or implement anything.

Plan: <plan text or path>
Decision it settles: <direction>
Current evidence: <code/config/runtime facts, constraints, non-goals>

Try to falsify readiness: unsupported assumptions or benefits, simpler viable
alternatives, results without an evidence chain, boundaries without real
owners or contracts, generalization before one path works, acceptance weaker
than the claim, and relevant compatibility/security/concurrency risks.
Treat the planner's recommendation as a hypothesis. Do not reject for style.
State when evidence is missing.

Return: P0/P1/P2 findings (problem, evidence, consequence, correction);
unsupported claims; missing simpler alternatives; residual risks;
verdict approve | approve-with-changes | reject.
```
