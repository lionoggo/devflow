# Industry Comparison

Place the researched implementation among common approaches so the reader
understands what is conventional and what is distinctive. This is positioning,
not a recommendation.

## Trigger

Run it only when the user asks for it (对比业内 / 业界怎么做 / 有没有类似方案).
For a document meant for others to borrow ideas from, offer it in one line
at the end instead of running it. Skip it when local behavior is not yet
understood.

## Method

1. Understand the local implementation first; comparison without it is noise.
2. Abstract and sanitize the problem into public technical terms. Never send
   private code, internal identifiers, secrets, or unpublished product details
   to an external service.
3. Delegate web and documentation search to the `researcher` subagent when
   available. Prefer primary sources: official docs, source code, papers,
   maintainers' design notes.
4. Inspect at most three credible approaches deeply. Use at most two
   meaningful query refinements.
5. For each approach record: core idea, how the local implementation differs,
   tradeoffs, and source links.

## Output

A short section or table: approach, core idea, difference from this project,
source. Every row cites a source.

## Limits

- Absence of results is inconclusive, not evidence of novelty.
- If search is blocked (auth, rate limits, no tooling), say so and continue
  with local findings.
- If the user moves to "which should we adopt" or "how should we change ours",
  stop and recommend `devflow-plan`.
