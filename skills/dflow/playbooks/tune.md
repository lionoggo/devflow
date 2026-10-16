### 调优 (tune)

**Make a repeated mistake impossible, at the highest level that works.** From
pstack `correct`, `reflect`, and `authoring-a-skill`. Principles: 结构化教训,
先减后加, 真实证据.

1. Name the mistake class with evidence: the user's corrections in this
   conversation, recent commits and reverts, review comments, run logs. It
   counts as a class once it happened twice; a one-off is not a lesson.
2. Pick the highest level that works, in this order, and say why each higher
   one does not:
   1. Structure: remove the wrong way (one owner per state, one supported
      path, delete the old way an agent would copy).
   2. A check: a type, lint, script, or hook whose failure message names the
      right way.
   3. A behavior test.
   4. Written rules, last, only for judgment calls.
3. Prove the new check fails on a reproduction of the real past mistake, then
   passes on the corrected state. Keep both outputs.
4. Editing a skill: keep only text that changes a decision; delegate to other
   files by path instead of restating; check that the frontmatter has `name`
   and `description` and every referenced path exists. When the skill has a
   test script, run it.
5. Global rule files (`~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`,
   `~/.claude/settings.json`) and anything outside the goal are ask-first:
   show the exact change and wait. Repo files in scope: edit and commit
   locally.
6. Reflect on a session (user says "总结教训", or 复盘 hands lessons over):
   list candidate lessons, drop one-offs and anything already covered, and
   route each kept one to a level from step 2. Apply repo-scoped ones;
   propose global ones.

**Reply:**

```text
**调优**：<一句话>
- 错误类型：<描述 → 出现过的证据（至少两次）>
- 选的层级：<结构 / 检查 / 测试 / 文字>。更高层级为什么不行：<…>
- 证明：<在过去那次错误上失败的输出 → 修正后通过的输出>
- 改动：<文件和提交；全局文件写"待你确认"和具体改动>
```
