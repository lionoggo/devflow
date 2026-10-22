# Plan review

Review to reduce real risk, not as a ritual. It tries to disprove readiness.

- **Default before a plan is final:** cross-model, read-only:
  `codex exec -s read-only --ephemeral --skip-git-repo-check -C <repo> -o <out.md>`
  with the prompt below on stdin. Give it the plan path and the evidence, not
  your reasoning or your verdict. When the plan rests on a requirement or
  spec document, give that document too and keep the 需求对照 line in the
  prompt; otherwise drop that line. Tell it this is a non-interactive run that
  must finish its whole analysis in one reply.
- Also run the readiness questions in `plan-shape.md` yourself.
- The planner stays the owner: check each finding against current evidence,
  then adopt, defer, or reject it with the reason. At most two rounds; product,
  architecture, security, or public-contract disagreements go to the user.
- codex unavailable or failing: report "未审查：<原因>". No Claude
  self-review in its place.

Lenses, only the relevant ones: ownership and boundaries · outcome closure ·
vertical slice vs premature generalization · generality across inputs ·
compatibility and migration · security and reliability · performance ·
testability · user experience · what could be deleted.

```text
你是独立的只读评审者，只评审下面的方案，不修改文件、不实现。这是非交互运行，请在本次回复内完成全部阅读和分析。

方案：<路径>
它要解决的决定：<方向>
当前证据：<代码、配置、运行事实；约束；非目标>
需求对照：方案依据 <需求文档路径>。逐条列出方案引用范围内、在验收里没有对应的需求条目（包括一条需求里被漏掉的子项），方案明确写了不做的除外。

尝试证伪"方案可以执行"：没有依据的假设或收益、更简单的可行做法、没有证据链的结果、没有真实负责方或契约的边界、一条路径还没跑通就先泛化、比承诺弱的验收、只对个例成立的修法，以及相关的兼容、安全、并发风险。把作者的推荐当作假设。不因文风否决。证据缺失时直说。

用简体中文返回：P0/P1/P2 问题（问题、证据、后果、改法），每级最多 5 条，其余列入"未采纳的次要意见"；无依据的说法；漏掉的更简单方案；剩余风险；结论：可以执行 / 修改后执行 / 不可执行。
```
