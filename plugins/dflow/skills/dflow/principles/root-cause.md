# 找根因 (fix root causes; attack the premise)

- Reproduce first, on the surface where the user saw it. Ask the user only
  after driving it as far as the tools reach, with the specific reason.
- Ask why until you reach the cause. When state is unclear, instrument and
  read it as the code runs; do not guess.
- Ask whether the state that triggered the symptom is legitimate. If it is,
  handle it where the code broke; that is the fix. If it should never exist,
  find what produced it: guards, retries, swallowed errors, and clamped values
  only hide it. A workaround that needs a paragraph to justify it means the
  code is wrong.
- Fix the pattern, not the instance: search for the same shape and fix all.
- When evidence refutes a hypothesis, revert what it motivated.
- "Fails after restart": suspect stale state (config, cache, lock files) first.
- A second fix failing on the same premise: write the premise down, then make
  one observation that would come out differently if it were false (look at
  how the failures are distributed, not only how large), as a rerunnable
  check. Refuted: look for what the failures share. Confirmed: ask the next
  why. Remove the condition instead of compensating for it. No next fix
  before the premise is written and tested. Run the cross-model review here
  (see `SKILL.md`).
- If the deciding fact took a deep dig, propose the cheap always-on signal that
  would have shown it at first look.
