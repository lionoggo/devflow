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
6. A mistake that shows up twice in the trail is a lesson; offer 调优 for
   it, do not edit skills here.
7. Write everything you checked to `<retro dir>/retro.md`: verification
   (what ran, on which commit, what was reused and why), each log mismatch,
   the danger scan, P2 findings, lessons, and the full review's path. This
   file is where the detail lives; the reply only points at it.

**Reply:** as pstack does. A short summary in your own words (how the run
went, what is still open, what the user needs to decide), written per
**Reply** in `SKILL.md`; no fixed lines or headings. It never says nothing
needs the user while the section below has a P1. How you checked (review
reruns, danger scan, log matching) stays in `retro.md`. Then end with:

```text
**需要你注意**
审查：<模型>（没审就写"未审查：<原因>"）
- P1 <影响>。见日志 <时间> / 代码检查 <path:line>。
- 未核实：<哪条说法，缺什么>。
详情：<retro dir>/retro.md
```

Each item is at most two sentences: the impact, then the pointer. How it
happens, how to fix it, and why it did no harm this time stay in the review. Only P1s, 未核实 claims, danger-scan hits, and
a lesson worth 调优 go here; P2s and the rest stay in `retro.md`. Nothing
to flag: `审查：<模型>，无`.
