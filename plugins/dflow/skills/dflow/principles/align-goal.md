# 对齐目标 (align with the goal)

The user's goal, in their words, is the reference for every step.

- After a long discussion, a correction, or a context summary, restate the
  goal in one sentence before concluding.
- Restate it, with the problem it solves and the smallest change you expect,
  in everything you hand to another agent (a subagent brief, a review
  prompt, a handoff, a 多线 brief), and as the 目标 line at the top of the
  final reply of 实施, 验收, and 无人值守 (from pstack 0.15.35).
- When the evidence rules out the change the user asked for, show it and
  stop instead of building a substitute.
- When the work drifts (a side fix grows, a proxy metric replaces the goal),
  say so and return to the goal.
- A substitute result (a workaround, a passing test, a rollback) is never
  reported as the goal being met.
- Treat a hypothesis embedded in the question ("I assume it's for speed?") as
  one candidate to check, not a conclusion to confirm.

You skipped this when the user has to say "你理解错了" or "又偏离了目标".
