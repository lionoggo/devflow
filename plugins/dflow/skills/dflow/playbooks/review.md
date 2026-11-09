### 评审 (review)

**Give an independent verdict on a plan, code change, or two approaches,
sorted by what must change. Do not edit.** From pstack `interrogate` and
`references/plan-review.md`. Principles: 以现状为准, 先减后加, 通用解, 真实证据.

1. State the intent of what is under review in one paragraph, from the
   user's message, the doc, commit messages, and the code. Unclear intent:
   state your best reading and go on.
2. Gather the scope: the doc path, `git diff <base>...HEAD`, or the named
   files, plus the context files a reviewer needs.
3. Invoking this playbook counts as asking for an independent review. Run the
   other model read-only (`SKILL.md` **Cross-model review**), giving it the
   intent, the scope, and the lenses below, never your own verdict. Use the
   prompt in `references/plan-review.md` for a plan; for code, ask the same
   questions plus the steps in `references/impact.md`, and when the code
   implements a plan or spec, give it those docs and the two requirement
   questions in `SKILL.md` **Cross-model review**, and ask for the proof
   that section's **Findings need proof** names. Keep its output file.
4. Review it yourself in parallel against the same lenses, holding your own
   findings to the same proof. For code, run `references/impact.md`: name
   the one fact the change is safe because of and its evidence level.
5. Rerun or read each finding's proof from both sides. Put each in one
   bucket:
   - 必须改: shown and blocking, per **Findings need proof**. At most five;
     each with location, the proof you reran, and the smallest change.
   - 值得考虑: shown but not blocking (a follow-up).
   - 未证实: no proof, or your rerun did not show it; say which.
   - 不采纳: disproved by the code or a run, with the disproof.
   Findings both models raised on their own rank highest.
6. Comparing two approaches: list the hard constraints first and drop what
   fails them; compare the rest item by item; recommend one.

Lenses, only the relevant ones: goal fit · generality across inputs · what
could be deleted · boundaries and ownership · compatibility and migration ·
safety and reliability · testability · user experience.

**Reply:**

```text
**评审**：<可以执行 / 修改后执行 / 不可执行>。<一句话>
- 评审模型：<实际审查模型，按 references/hosts.md（输出文件路径）+ 主会话；或 未审查：原因，下面只是主会话意见>
- 必须改：<P0/P1，位置 → 问题 → 复现（命令与输出，或引用的行）→ 最小修改；最多 5 条>
- 值得考虑：<已证实、不阻塞的后续事项>
- 未证实：<意见 → 为什么没证实>
- 不采纳：<意见 → 反证>
```
