# 找根因 (fix root causes; attack the premise)

- Reproduce first, on the surface where the user saw it. Ask the user only
  after driving it as far as the tools reach, with the specific reason.
- Ask why until you reach the cause. When state is unclear, instrument and
  read it as the code runs; do not guess.
- No guards that silence the symptom (a null check over a crash). A
  workaround that needs a paragraph to justify it means the code is wrong.
- Fix the pattern, not the instance: search for the same shape and fix all.
- When evidence refutes a hypothesis, revert what it motivated.
- "Fails after restart": suspect stale state (config, cache, lock files) first.
- A second fix failing on the same premise: write the premise down, check it
  with evidence across all affected cases, and question it before the next fix.
  Run the cross-model review here (see `SKILL.md`).
- If the deciding fact took a deep dig, propose the cheap always-on signal that
  would have shown it at first look.
