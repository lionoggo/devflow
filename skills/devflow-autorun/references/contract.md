# Contract template

Write `.devflow/<slug>.md` in the reply language. The user owns this file, and the
run never edits it.

```text
# 自动运行契约：<slug>

- 阶段：<stage id from the plan, e.g. P1>
- 计划契约：<planned contract id, e.g. p1-godot; a retry such as p1-godot-r2 keeps the original id>
- 计划文件：<plan path relative to the repo root, or omit>
- 目标：<user-visible result>
- 非目标：<excluded behavior>
- 依据：<approved plan path, or 无>
- 完成条件（每条是命令和期望结果，全部满足才算完成）：
  - P1：`<command>` → <exit 0 / output contains …>
- 人工项（不计入完成；收尾时交给用户检查）：<无, or one item per line below>
  - <id>：<what the user checks>
- 写入范围：<path prefixes ending in / or globs>
- 受保护路径：<tests, fixtures, and scripts the conditions run, plus additions>
- 分支：autorun/<slug>；允许本地提交：是（push、合并、发布始终禁止）
- 工作区：当前（已确认干净） | worktree <path>（用户要求创建）
- 预算：最长 <8> 小时，最多 <40> 轮
- 花费：命令 `<read-only command printing this run's cumulative USD>`；上限 $<n>（optional; omit when not tracked）
- 额外停止条件：<tighter rules, or 无>
- 基线：<arming-time output of each condition, summarized>
```

`阶段`, `计划契约`, `计划文件`, `花费`, and the 人工项 lines are read by
`scripts/status.py register` with fixed prefixes, so keep their exact form.
`阶段` and `计划契约` are required. The cost command must be read-only, call no
model or network, and finish within 10 seconds; say what it counts.

A default can be tightened but not loosened. A done condition is never
relaxed during the run. Changing one is a user edit to this file, followed by
a new arming.
