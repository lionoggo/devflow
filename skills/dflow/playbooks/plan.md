### 方案 (plan)

**Turn an idea into a plan the user can approve. Do not implement here.** From
devflow-plan; pstack `prototype` and `multi-phase-plan` hand-back. Principles:
先减后加, 通用解, 以现状为准, 不停下等人.

Enter at the earliest open stage; a small clear request gets a few lines (what
changes, how to check it), not the full shape.

1. **Requirements**, when the intent is fuzzy.
   - Restate the need as goal, scenarios, non-goals, constraints, and success
     criteria the user can observe. Separate the need from any means the idea
     implies ("加缓存" is a means; "导出慢" is the need).
   - When the user points at something they see, first work out what it is and
     who controls it; say early if it is outside this repo's control.
   - Answer every factual question yourself (code, config, runtime, a quick
     experiment). Ask only product or preference questions, at most three,
     each answerable directly.
2. **Direction**, when the approach is open.
   - Settle factual forks by prototype in the scratchpad (smallest script or
     page that shows the behavior), not by asking.
   - Compare only credible directions, ranked by real cost; prefer the
     smallest reversible one. One that adds a public contract, durable state, a
     service, or a migration says why existing boundaries cannot do it. For
     build-vs-reuse or unfamiliar architecture, use
     `references/prior-art-research.md`.
   - Recommend one with tradeoffs; the user picks the direction.
3. **Plan**, when the direction is picked.
   - Write it in the shape of `references/plan-shape.md`; acceptance comes
     from the confirmed requirements.
   - Save it to `docs/plan-<topic>.md` in the relevant module and commit it
     locally, unless the user asked to keep it in chat.
   - Before calling it final, run the cross-model review with
     `references/plan-review.md`; adopt, defer, or reject each finding with
     evidence, at most two rounds.
   - Hand back once: the plan path, the review outcome, and one question:
     execute it? Execution starts on the user's go, under 实施 or 无人值守.

**Reply:** at the three decision points use these shapes; otherwise plain
conversation.

```text
**需求待你确认**
- 我的理解：<需求一句话，不含做法；标出假设>
- 现状：<1–3 条决定性事实，带位置>
- 需要你定：<1–3 个产品或偏好问题，尽量带选项>

**方向待你选择**
- 需求：<一句话>
- 可选方向：<每行一个，带代价>
- 推荐：<哪个，为什么>

**计划就绪**：<路径>
- <目标、关键决定、验收，按 plan-shape 的要点>
- 审查：<codex 结论与处理；或 未审查：原因>
- 要按这个方案执行吗？
```
