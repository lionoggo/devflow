### 验收 (verify)

**Establish with observed evidence whether the result meets the request.**
From devflow-verify and pstack `prove-it-works` / `create-verification-skill`.
Principles: 真实证据, 对齐目标, 不停下等人.

1. Pin the candidate (workspace, diff, or commits) and the criteria. Take
   criteria from the latest request, then an approved plan's acceptance (keep
   its labels), then a debug diagnosis. Code and closeout reports show what
   was built, never permission to lower the bar. Without a plan, derive a few
   criteria from the user's words, mark them derived, state them in a few
   lines, and start. Ask once only when the request leaves open a meaning that
   flips pass or fail (units, semantics, boundaries) and nothing can settle it.
2. Pick who verifies. A cross-module or high-risk change (a public contract,
   stored data, money, concurrency; user-facing alone is not enough) that
   this session built: start one subagent without edit tools (the Explore
   type, model `sonnet`), give it only the criteria and the candidate (diff
   or commits), never your implementation reasoning, and have it run the
   evidence; then check its evidence yourself before using it. Long context
   or the user asks: a new session through 交接 (`playbooks/handoff.md`).
   Otherwise verify here, judging only from evidence observed in this
   playbook, not from reasoning made while building.
3. Find the driver for the real usage path. If the project has a verification
   skill (`.claude/skills/verify-*` or one named in its docs), use it.
   Otherwise use the existing harness (Playwright, CLI, curl, game runner).
   When a user-facing project has none, say so in the reply and offer to
   generate one with `references/create-verification-skill.md`.
4. For each criterion, run the cheapest evidence at the level it needs; a
   user-visible claim needs one observation on the real path. Evidence that
   touches shared or external state (real data, messages, payments, deploys,
   dependency installs) asks first.
5. Run end-to-end items last, on the final integrated state (fresh build, real
   configuration). Something only a human can judge (look and feel, a real
   external account) becomes a short checklist for the user, not a claim.
6. Classify each failure: product defect, harness, environment, or baseline
   (failing before the change).
7. Repair confirmed in-scope product defects without asking, unless the user
   said "只验收" or the candidate is someone else's unmerged work: smallest fix,
   rerun the affected evidence and nearby regressions, commit locally. Fix
   harness problems only in maintained test code. Stop after three rounds on
   the same defect, or when a repair needs an architecture or public-contract
   change, and report.
8. For several criteria or an inherited plan, keep the matrix in
   `references/acceptance.md`.

Read old versions with `git show <rev>:<path>`; never checkout, reset, stash,
or clean to get a baseline.

**Reply:**

```text
**验收结论**：<通过 / 未通过 / 部分通过 / 无法完成验收>。<一句话>
- 标准与证据：<每条：标准 → 怎么查的（层级）→ 结果；推导出的标准注明>
- 问题与修复：<确认的缺陷，修复提交>
- 未覆盖：<没观察到的项、给你的人工检查清单、环境或基线问题>
```

通过 = every required criterion observed at its level. 未通过 = any observed
failing. 部分通过 = none failed, some could not be observed. 无法完成验收 =
nothing required could be observed.
