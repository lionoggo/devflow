# Prior-Art Research

Use external precedent only when it can change the decision. This research is
read-only and tool-neutral; use an available GitHub connector, GitHub CLI,
web search, documentation source, or equivalent read surface.

## Trigger

Research prior art when it can clarify:

- build versus reuse for a library, protocol, component, or service;
- an unfamiliar architecture, workflow, or tool integration;
- compatibility, migration, scale, security, or operational risks;
- whether successful or failed implementations should change the candidate set.

Skip it when local behavior is not yet understood, the choice is primarily an
internal product policy, the change is narrow and already follows a proven local
pattern, or useful search terms would disclose sensitive information.

## Method

1. Abstract and sanitize the problem into public technical terms. Never send
   private code, internal identifiers, secrets, customer data, or unpublished
   product details to an external service.
2. Search broadly for relevant projects, standards, discussions, or designs.
   Then inspect concrete code only inside credible candidates.
3. Evaluate relevance, maintenance activity, adoption evidence, license,
   architecture fit, integration cost, and known limitations. Inspect issues,
   discussions, and failure reports rather than relying only on README claims,
   popularity, or stars.
4. Record what is reusable, what does not transfer to the current system, and
   how the precedent changes the decision. Treat absence of results as
   inconclusive, not as evidence that an idea is novel or invalid.

## Bounds

- Use at most two meaningful query refinements.
- Deeply inspect at most three credible candidates unless the decision remains
  high risk and another candidate is likely to change it.
- Stop when additional research is unlikely to change the candidate set,
  recommendation, or risk assessment.
- If authentication, rate limits, unavailable tooling, or missing public
  analogues block research, report the limitation and continue from local
  evidence when safe; do not make external research a planning prerequisite.

## Output

Summarize only decision-relevant findings:

- sources or projects inspected;
- reusable patterns and important failure modes;
- compatibility, license, maintenance, or adoption concerns;
- the concrete effect on the current recommendation;
- remaining uncertainty.
