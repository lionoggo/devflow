### 排查 (debug)

**Every changed line traces to runtime evidence.** From pstack `bug-fix`, `tdd`,
and devflow-debug. Principles: 找根因, 通用解, 真实证据, 测行为.

1. Reproduce it yourself on the surface where the user saw it (page, CLI,
   service, game). If it will not reproduce, synthesize the trigger, tighten
   conditions, or instrument until it fires. Ask the user only after driving it
   as far as the tools reach, with the specific reason.
2. Narrow the cause: list candidate hypotheses, then rule them out with runtime
   evidence, each step cutting the most remaining space. Instrument instead of
   guessing. For a regression, compare with a known-good version via
   `git show <rev>:<path>` or `git log`; never checkout, reset, or stash.
3. Decide the fix at the root and check it is general: which other inputs or
   projects have the same pattern. When the cause is data, config, or
   environment, fix that or give the recovery step instead of changing code.
4. If the user said "先别改代码" or only asked for the cause, stop here and
   reply. Otherwise go on without asking.
5. When there is a cheap local test path, write the failing test first and see
   it fail for the intended reason; skip it when the test would be expensive,
   integration-heavy, or unclear. Never edit a test to match a wrong fix.
6. Make the smallest fix the evidence justifies. Revert anything a refuted
   hypothesis motivated. Fix every instance of the pattern.
7. Rerun the original reproduction on the same surface, plus the relevant
   tests. Then `SKILL.md` **After any change**: smoke nearby inputs and the
   failure path, and write the 影响面 line. Commit locally (test first, then
   fix, when there is a test).
8. If this is the second failed fix for the same symptom, stop fixing: write
   down the shared premise, run the cross-model review, and change approach.

**Reply:**

```text
**结论**：<已修复 / 原因已确认未修 / 未确认 / 受阻> — <原因一句话>
- 证据：<最小的决定性证据>
- 修复：<改了什么，提交号；或建议的改法 / 恢复步骤>
- 影响面：<见 SKILL.md>
- 通用性：<还覆盖哪些情况，查过哪些>
- 验证：<复现前后的真实输出；测试结果；没跑的写原因>
- 我做的选择：<选择 → 怎么改回；没有就省略>
```
