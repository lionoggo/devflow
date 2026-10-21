# Contract template

Write `.devflow/<slug>.md` in the reply language. The user owns this file, and the
run never edits it.

```text
# 自动运行契约：<slug>

- 目标：<user-visible result>
- 非目标：<excluded behavior>
- 依据：<approved plan path, or 无>
- 完成条件（每条是命令和期望结果，全部满足才算完成）：
  - P1：`<command>` → <exit 0 / output contains …>
- 人工项（不计入完成；收尾时交给用户检查；计划已列的不重复）：<无, or one item per line below>
  - <id>：<what the user checks>
- 写入范围：`<path prefix ending in />`、`<glob>`（each item in backticks）
- 受保护路径：`<tests/>`、`<fixtures>`（each item in backticks: tests, fixtures, and scripts the conditions run, plus additions）
- 分支：autorun/<slug>；允许本地提交：是（push、合并、发布始终禁止）
- 工作区：当前（已确认干净） | worktree <path>（用户要求创建）
- 预算：最长 <8> 小时，最多 <40> 轮
- 额外停止条件：<tighter rules, or 无>
- 基线：<arming-time output of each condition, summarized>
```

`scripts/arm.sh` reads these lines by their fixed prefixes, so keep their exact
form: `写入范围`, `受保护路径`, `分支`/`允许本地提交`, and `预算：最长 <n> 小时`
are required; `目标` and `基线` go into the start row.

A default can be tightened but not loosened. A done condition is never
relaxed during the run. Changing one is a user edit to this file, followed by
a new arming.
