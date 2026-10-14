# HTML Demo

An interactive companion page for one mechanism that static text and diagrams
explain poorly. The Markdown document stays the canonical write-up; the demo
links back to it and never carries claims the document lacks.

## When

- The user asks for it, or
- A key mechanism depends on time or parameters (cycle/period detection,
  state machines, animation timing, thresholds whose effect is the point),
  in which case offer it in one line rather than building it unasked.

One demo per mechanism. Do not turn the whole report into a web page.

## Faithfulness

- Data comes from the project's own code, not a re-implementation. Run the
  real function on inputs taken from tests, fixtures, or clearly labeled
  synthetic signals, as a read-only computation with no side effects, and
  embed the outputs (JSON) in the page. The page only visualizes. Run it only
  in an already-available environment (see the SKILL.md boundaries); otherwise
  port the formula and say it was not cross-checked against the real function.
- If the page must recompute something interactively (for example a
  threshold slider), port only that small formula, cite its `path:line`, and
  cross-check the port against the embedded outputs of the real function.
- Label every input as test fixture, default config, or synthetic. Never
  present synthetic data as real production measurements.
- Synthetic inputs must actually exercise the rule they illustrate: avoid
  perfectly exact repeats where a tolerance never matters, add noise, and
  place values near the threshold on both sides when the threshold is the
  point. If a case only works because of a configured constant, say so.
- State precisely which steps ran through project code and which the script
  constructed (for example a hand-built distance matrix instead of the
  project's own feature extraction).
- Show the commit hash and link or path to the Markdown document.

## Delivery

- Default: a local, self-contained file next to the document
  (`docs/research/<topic>-demo.html`) with a full HTML skeleton, inline CSS
  and JS, embedded data, and no required network resources (web fonts, if
  any, must have system fallbacks). Give the path so the user can open it in
  a browser, and report its actual git status.
- Never publish to a hosted service (for example the Artifact tool) unless
  the user explicitly asks for a hosted page in the current request.
- Keep the data-generation script in the scratch directory (`scripts/scratch.sh`) and state in the reply
  how the embedded data was produced.
- After every edit, syntax-check the inline script (for example extract it and
  run `node --check`) and render the page once; text edits inside JS strings
  can break the whole page silently.
