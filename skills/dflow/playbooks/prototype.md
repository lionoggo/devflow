### 原型 (prototype)

**You own the design decision, not the code. The prototype is throwaway; the
real build goes through 实施.** From pstack `prototype`. Principles: 不停下等人,
真实证据, 先减后加.

This stage covers how a screen looks (layout, density, presentation). A fork
about behavior or timing is a minimal experiment under 不停下等人, not this
playbook.

1. Write down the one question the prototype answers ("报表用表格还是卡片").
   No question, no prototype: route to 实施.
2. In the scratch directory (`SKILL.md` **Scratch directory**), write one
   HTML file with two or three labeled variants behind switch buttons. Plain
   HTML/CSS/JS, CDN libraries at most; no framework, build tool, tests, or
   abstractions. Use realistic sample data from the repo when there is some.
3. Open it in a browser (a static server on a free port if needed) and take a
   screenshot of each variant. Without a browser or screenshot tool, say so
   and deliver only the file and the recommendation; never claim you looked.
4. Compare the variants against the question: what each makes easy or hard
   to read, and where each breaks (long text, many rows, narrow screen).
   Taste stays the user's call; the screenshots are the material for it.
5. Stop any server you started. Never commit the prototype or copy it into
   the source tree. When the user picks, hand the choice to 实施.

**Reply:**

```text
**原型**：<要回答的问题>
- 变体：<每个一行：名字 → 截图路径 → 长处 / 短处>
- 推荐：<哪个，为什么；口味问题由你定>
- 文件：<HTML 路径>（一次性原型，不提交；选定后按实施剧本重做）
```
