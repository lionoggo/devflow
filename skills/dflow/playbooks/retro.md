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
   the review the user reads. Reuse only a review this same conversation ran
   on the same log and HEAD; one from another conversation is rerun, since
   the tools or rules may have changed since, unless the user says to skip
   it. Unavailable: 未审查：<原因>.
6. A mistake that shows up twice in the trail goes under 值得记下的教训 with
   an offer to run 调优; do not edit skills here.

**Reply:** fixed order, sections only when they have content. The first
two lines answer "how did it go" and "do I need to act"; what you decide
comes before the full flag list. Each fact is told once: decisions say the
choice, flags say the fact, 核对 says how far the trail can be trusted,
教训 adds only the pattern. Hard limits:
- 审查 is one short line: the model, and 复用 when reused. Why reuse was
  allowed goes under 核对.
- 等你决定 names each thing in words, never "第 1、2 项".
- 需要你注意 holds P1s and anything that bears on a decision, at most two
  sentences each: the impact and when it happens. No mechanism, no fix
  steps; those stay in the full review. P2s go under 其他发现, one line each.
- A flag points at a log row or moment; one found only by reading current
  code says 代码检查 <path:line>.

```text
<完成 / 部分完成 / 受阻 / 仍在运行>。<做成了什么、没做成什么，一句话>。共 <n> 个提交。
需要你：<无需操作 / 决定什么 / 提供什么，一句话>。

**等你决定**（有才写）
- <事项>。<现在保持什么，不决定会怎样>。

**需要你注意**
审查：<模型>[，复用]（没审就写"未审查：<原因>"）
- <P1/P2> <影响>。<何时触发或现状>。见日志 <时间> / 代码检查 <位置>。
（没有就写"审查：<模型>，无发现"，与上一行合并）

**核对**
- 验证：<关键结果；重跑了什么；哪部分未核实及原因；审查复用的依据>
- 日志：<全部对得上 / 哪几行对不上>。危险命令扫描：<未命中 / 哪几条，是否正当>
- 其他发现：<P2 和不影响眼前决定的问题，一行一条，指向证据；没有就省略>
- 教训：<同一类问题出现两次的，只写归纳，问要不要走调优；没有就省略>
详情：<.dflow/<slug>.tsv>，先看 <上面指到的时间>；完整审查 <路径>。
```

Everything normal (goal met, checks pass, trail matches, review ran with no
flags) is three lines:

```text
已完成，验证通过。共 <n> 个提交。无需你操作。
审查：<模型>，无发现。日志核对一致，危险命令扫描未命中。
详情：<.dflow/<slug>.tsv>。
```
