---
name: devflow-plan
description: "Take an idea, improvement, product or architecture choice, technology selection (选型/选型调研), or planning request from a fuzzy intent to confirmed requirements, a chosen direction, and an implementation-ready plan. Use when the user has an idea (我有个想法/想做), asks for a 方案/设计/计划/plan, or unresolved requirements or tradeoffs will shape the implementation. Do not use for explaining existing code (devflow-research) or diagnosing an observed failure (devflow-debug)."
---

# Devflow Plan

Turn an idea into a plan in up to three stages. Read-only: do not edit code
from this skill.

## Stages

Enter at the earliest stage that is still open and skip the rest of what is
already settled. Talk naturally; name the stage only when asking the user to
confirm requirements, choose a direction, or approve a plan. A small, clear
request gets a few lines (what changes, how to check it): do what was asked and
ask only when a real ambiguity would change the result.

1. **Requirements** — when the intent is fuzzy.
   - Restate the idea as goal, users/scenarios, non-goals, constraints, and
     success criteria written as results the user can observe. Separate the
     need from any solution the idea already implies ("add a cache" is a
     means; "export is slow" is the need).
   - When the user points at something they see (a screenshot, a UI area, an
     error), first work out from what they showed what it is and who controls
     it; then check code, configuration, and runtime facts. If the target is
     outside what this repository controls (browser, OS, another app), say so
     plainly and early. Don't ask for facts the repository can answer; when it
     is unclear what the user is pointing at, one short question beats
     guessing from code.
   - Ask at most three questions at once, only ones that change direction;
     each asks one thing and can be answered directly.
   - End with a short requirements summary for the user to confirm or correct;
     keep any means out of it and list them separately for the next stage.
2. **Direction** — when requirements are settled but the approach is not.
   - Compare only credible directions; prefer the smallest reversible one. A
     direction that adds a public contract, durable state, a service, a
     migration, or moves an ownership boundary must explain why existing
     boundaries cannot meet the need.
   - Rank directions by their real cost. When the exact goal is only reachable
     at a disproportionate cost (such as forking a browser), say so plainly and
     recommend the closest reasonable option, stating what it gives up.
   - Recommend one with tradeoffs and risks; the user selects.
3. **Plan** — when the direction is selected.
   - If the direction depends on a costly premise (building a browser,
     switching stacks, a paid service), confirm that premise in one question
     before writing the plan.
   - Write the plan once, in the shape of `references/plan.md`; its goal,
     non-goals, and acceptance come from the confirmed requirements. Keep
     local algorithms, helpers, and file layout open unless they change an
     approved boundary or acceptance.
   - Deliver it exactly once: in a host plan mode, submit it through that
     mode's approval step; otherwise present it in chat and, unless the user
     already asked to implement it, ask once whether to execute. Approval makes its acceptance criteria the basis for
     implementation and verification.

## Files

Keep everything in chat by default. Write `docs/plan-<topic>.md` (in the
relevant module) only when the user asks, repository rules require it, or the
work will continue in another session; a separate requirements document (PRD)
only when asked. A plan file grants no implementation authority by itself.

## Optional

- External precedent (build vs reuse, unfamiliar architecture):
  `references/prior-art-research.md`.
- Plan review, self or independent: `references/review.md`.

## Output

Write for the user: conclusion first, plain language, no internal status codes
or English field names; omit empty items. Use the shapes below only at the
three decision points; other turns are ordinary conversation. The headings
show the shape, not fixed text.

Requirements stage:

```text
**需求待你确认**
- 我的理解：<the need in one sentence, without any means; mark assumptions>
- 现状：<1–3 decisive facts with locations>
- 你提到的做法：<only when a means differs from the need; compared in the next stage>
- 需要你确认：<1–3 questions, one decision each, with options when possible>
```

Direction stage:

```text
**方向待你选择**
- 需求（已确认）：<one sentence>
- 可选方向：<one line each, with its cost>
- 推荐：<which and why>
```

Plan stage: headed **计划就绪**, the plan in the shape of `references/plan.md`,
ending with one question: execute it?
