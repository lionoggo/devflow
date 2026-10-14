### 实施 (build)

**Carry an approved plan, or a clear "你来改", to a verified, committed
result without stopping.** From devflow-impl and pstack `feature`. Principles:
小步可验证, 真实证据, 先减后加, 不停下等人.

1. State in two or three lines: the goal, the done checks (keep the plan's
   acceptance labels; without a plan, derive A1, A2… from the request and mark
   them derived), and the approach. Then start; do not wait.
2. Name the data shape the change works on before writing logic, and where it
   lives in the current code. When the change touches a contract others can
   observe (`SKILL.md` **After any change** step 3), run
   `references/impact.md` before editing and say so in the route line.
   Changing an interface inside the repo: migrate every caller in the same
   change and delete the old shape; no compatibility layer unless external
   users depend on it.
3. Work in units, riskiest first, each ending in a check. After each passing
   unit, commit locally with its own message. A unit that did not move its
   check is reverted.
4. Stay inside the plan: no durable state, public contract, migration, or
   ownership change it does not require. A plan that cannot be met as written,
   or a product decision it left open, is reported; do the rest first.
5. Preserve unrelated dirty work; never stage it. Reuse existing checks before
   adding a permanent test; add one only for a named, credible regression.
6. Follow the plan's stages in order; each stage's check passes before
   dependent work starts. When a stage remains and the user asked for the whole
   plan, continue into it.
7. Finish with 验收 (`playbooks/verify.md`) for user-visible results; an
   end-to-end promise needs an end-to-end observation. Then `SKILL.md`
   **After any change**: smoke beyond the main check and write the 影响面
   line.

Delegation: one subagent per independent slice only when it cuts total cost;
give it the scope, the data shape, and the check; review its diff yourself.

**Reply:**

```text
**结果**：<完成 / 部分完成 / 受阻> — <一句话>
- 提交：<sha 和标题，按顺序>
- 验收：<每个标签 → 证据（层级）→ 结果；没跑的写未验证和原因>
- 影响面：<见 SKILL.md>
- 改动的已有测试：<哪个测试的预期变了 → 为什么；没有就省略>
- 我做的选择：<选择 → 怎么改回>
- 下一步：<剩余阶段或未覆盖项；没有就省略>
```
