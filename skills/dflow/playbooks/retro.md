### 复盘 (retro)

**Walk the user through a run that kept a decision log, in review form: what
deserves a look first, then the rows it points at. Read-only.** From pstack
`show-me-your-work` ("catch me up on what you did last night"). Principles:
真实证据, 以现状为准.

1. Find the log in `.dflow/*.tsv` of this repo (not `*.units.tsv`). Only
   this repo: never scan other repos or other projects' transcripts; a run
   in another repo is reviewed from that repo.
   - A slug named: review only that one.
   - 全部 or all: every log written in the last day (file mtime), each
     through steps 2–7 on its own, with its own retro directory, `retro.md`
     and cross-model review.
   - Neither: review the newest. When several were written in the last
     day, first give a table, slug | 状态 | the last row's decision | log
     path, and say in one line that `/dflow retro <slug>` or `全部` reviews the
     others. 状态 comes only from these files: 运行中 when the lease
     `.dflow/<slug>.lock/lease` names a `pid` that is a live claude or codex
     process; else the last `close` row's decision (完成, 部分完成, 受阻);
     else 受阻 when the last row is `blocked`, 已暂停 when it is `pause`;
     else 未收尾 (a stale lease, or a log that never closes, as playbooks
     other than 无人值守 write).
   - None: there is no trail; say so, and go to 进展 for where things
     stand, or 调优 step 6 for lessons from this conversation.
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
   row, the main session crediting the user with an approval no user line
   gives) becomes a flag. Run `timeline.py --danger` on the same ids.
   Do not rerun the run's checks: tests and scripts can write files or make
   paid calls, and the transcript is the evidence. A check claimed with no
   run after the last edit is a flag. One whose result may differ now (the
   environment changed since) is 未核实, with the command in `retro.md`;
   run it only when the user asks. A check or review counts only for the
   commit it covered; a pass on an uncommitted tree, or a review before
   later fixes, reported as covering the final commit is a flag.
5. Cross-model review as `references/decision-log.md` step 4 (from Codex,
   the call in `references/hosts.md`), even when the
   closeout already ran one: the code may have changed since, and this is
   the review the user reads. Reuse only a review this same conversation ran
   on the same log and HEAD; one from another conversation is rerun, since
   the tools or rules may have changed since, unless the user says to skip
   it. Give the reviewer the closeout's review files too, and ask which of
   their findings were fixed only in part. Unavailable: 未审查：<原因>.
6. A mistake that shows up twice in the trail is a lesson; offer 调优 for
   it, do not edit skills here.
7. Write everything you checked to `<retro dir>/retro.md`: verification
   (what ran, on which commit, what was reused and why), each log mismatch,
   the danger scan, P2 findings, lessons, and the full review's path. This
   file is where the detail lives; the reply only points at it.

**Reply:** one log as below. Several (全部): first the table from step 1,
then one summary per log, then a single `**需要你注意**` merging every log's
items, each item starting with `<slug>：`, one `审查：` line per slug, and one
`详情：` line per slug.

One log, as pstack does: a short summary in your own words (how the run
went, what is still open, what the user needs to decide), written per
**Reply** in `SKILL.md`; no fixed lines or headings. It never says nothing
needs the user while the section below has a P1. How you checked (review
reruns, danger scan, log matching) stays in `retro.md`. Then end with:

```text
**需要你注意**
审查：<模型>
- <影响>。见日志 <时间> / 代码检查 <path:line>。
- 未核实：<哪条说法，缺什么>。
详情：<retro dir>/retro.md
```

The 审查 line is the model name only (or `未审查：<原因>`); whether it was rerun or
reused goes in `retro.md`. Items carry no P1 label, since only P1-level
issues go here. Each item is at most two sentences: the impact, then the
pointer. How it happens, how to fix it, and why it did no harm this time
stay in the review. Only P1s, 未核实 claims, danger-scan hits, and a lesson
worth 调优 go here; P2s and the rest stay in `retro.md`. Nothing to flag:
`审查：<模型>，无`.
