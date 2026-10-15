### 复盘 (retro)

**Walk the user through a run that kept a decision log, in review form: what
deserves a look first, then the rows it points at. Read-only.** From pstack
`show-me-your-work` ("catch me up on what you did last night"). Principles:
真实证据, 以现状为准.

1. Find the log: the slug the user names, else `.dflow/*.tsv` in this repo
   (not `*.units.tsv`), newest first. Several written in the last day: take
   the newest and name the others in one line. None: there is no trail; say
   so, and go to 进展 for where things stand, or 调优 step 6 for lessons from
   this conversation.
2. A lease (`.dflow/<slug>.lock/`) whose session is still alive means the
   run is still going: say so and review up to now. Never claim, check, or
   write that run's files.
3. Collect: the whole log, the manifest `.dflow/<slug>.md` when there is one,
   `git log --stat <base>..<branch>` (base from the manifest or the first
   `start` row), and `python3 -I scripts/timeline.py --say <session ids from
   the start rows>` into a `scripts/scratch.sh retro` directory. A missing
   transcript is 未核实.
4. Check the trail as `references/decision-log.md` step 2 does, but write no
   rows: each mismatch (a row with no matching action or commit, a commit in
   `<base>..<branch>` that no row names or that falls outside the timeline,
   evidence that does not resolve or does not show the claim, a pivot with no
   row, the main session crediting the user with an approval no user line gives) becomes a flag. Run `timeline.py --danger` on the same ids.
5. Cross-model review as `references/decision-log.md` step 4, even when the
   closeout already ran one: the code may have changed since, and this is
   the review the user reads. A review this conversation already ran on the
   same log and HEAD is reused. Unavailable: 未审查：<原因>.
6. A mistake that shows up twice in the trail goes under 值得记下的教训 with
   an offer to run 调优; do not edit skills here.

**Reply:**

```text
**需要你注意**（审查：<模型> / 未审查：<原因>）
1. <要看的问题> — 见 <ts> <阶段>「<该行决定的原话>」，证据 <指针>
（没有就写"无"）
**这次运行**：<完成 / 部分完成 / 受阻 / 仍在运行> — <一句话>；提交 <n> 个（<base>..<head>）
- 等你定的：<每个 gate 或按默认做的行：问题 → 现在的默认 → 怎么改>
- 日志对账：<一致 / 哪几行对不上>；危险命令：<无 / 哪几条>
- 值得记下的教训：<没有就省略>
- 自己翻：<.dflow/<slug>.tsv，读法见 decision-log 的"人怎么读">
```
