---
name: devflow-impl
description: "Execute an approved plan, specification, or implementation brief with a closeout checked against its acceptance criteria; optionally split it across bounded subagents or hand it off to another session or workspace. Use when the user asks to execute or implement a referenced plan/spec, delegate implementation, or write/launch a handoff prompt (交接 prompt) so another session can start or continue the work. Do not use for small direct edits or bug fixes that can be done in place, or when requirements are still open (devflow-plan)."
---

# Devflow Impl

Carry an approved plan to a checked result. What this adds to ordinary coding
is plan discipline:

- If an open product or architecture decision would change the result, or the
  plan cannot be met as written, stop and report it instead of deciding.
- Do not add durable state, public contracts, migrations, or ownership changes
  the plan does not require. Local helpers, algorithms, and layout are yours.
- Preserve unrelated dirty work. Reuse existing checks before adding a
  permanent test, and add one only for a named, credible regression.
- Follow the plan's stages in order when it has them; each stage's check
  passes before dependent work starts.
- If the source has no acceptance criteria, derive a few labeled ones (A1, A2…)
  from its goal and state them before editing.
- Keep the plan's acceptance labels. Never silently weaken or drop one; an
  end-to-end promise needs an end-to-end observation.

Optional: split across subagents (`references/delegation.md`); run in another
session or workspace (`references/handoff.md`). Do not stage, commit, push,
merge, rebase, or amend from this skill.

## Closeout

Write for the user: conclusion first, plain headings in the reply language, no
internal status codes or English field names; omit empty items. The headings
below show the shape, not fixed text.

```text
**结果**：<完成 / 部分完成 / 受阻> — <brief result>
- 改动：<scope>
- 改动的已有测试：<each existing test whose expected behavior changed → why; omit if none>
- 验收：<each label → evidence (level) → result; E-items not run as 未验证 with why>
- 未覆盖：<unverified or blocked items; baseline failures kept separate>
- 下一步：<when plan stages remain: the next stage's goal, acceptance, and
  whether to run it here or in a new session; wait for the user's go-ahead
  unless they already asked for it; omit otherwise>
```

For a small change, point the user to what to look at (diff, page, command
output) instead of suggesting a formal verification.
