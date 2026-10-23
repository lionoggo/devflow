### 交接 (handoff)

**Write the prompt that lets another session or agent continue without this
conversation. Delivering it is an outside action: the user says when.** From
devflow-impl `handoff.md`. Principles: 以现状为准, 对齐目标.

1. Pick the carrier. Plan approved, nothing built: the plan file plus a
   one-line prompt pointing to it. Work in progress: the full prompt below.
   Save it to a file when it is long or the user asks.
2. Pin the target state yourself: absolute repo path, branch, HEAD, dirty and
   untracked files, setup needed. Keep the current workspace; another one
   only when the user named it.
3. Fill the prompt. Write it through `references/unslop.md`; plain words, no
   terms the receiver never saw.
4. Show it to the user. Deliver (Orca, a new session, a subagent) only when
   the user says so; then stop your own writes, confirm delivery, and report
   the target. Never resend until non-delivery is confirmed.

Leave out transcripts, raw logs, credentials, and unrelated file contents.

```text
你负责 <实现已批准的范围 | 排查 <问题> | 调研 | 设计 <主题>>，仓库 <绝对路径>。

先读：<规则文件>，<方案或说明>，<关键文件>
目标：<一段话>
不做：<范围外>
用户的原则：<讨论中定下的原则和偏好，短的用原话>
已定：<选择>；未定：<无，或由谁定>
完成条件：<A1..An 及验证方法；或要回答的问题和需要的证据>
现状：<分支、HEAD、未提交和未跟踪的文件、环境>
进展（还没开始就省略）：
- 已完成：<结果和证据>
- 剩余：<标签、步骤或问题>
- 过程中的选择：<选择和原因>
- 已知死路：<试过不行的、排除了的、要避开的>
约束：保留无关改动；只改 <范围，或只读>；<架构约束>

开始前先核对分支、HEAD 和未提交文件是否与"现状"一致；不一致就停下报告差异。
已完成的不要重做，从"剩余"的第一项开始。这里说已通过的检查，宣布完成前在真实产物上重跑一次。
用 <入口：Claude 用 /dflow，Codex 用 $dflow:dflow> 开始，按对应流程做；不要再转交，不要换工作区。
```

**Reply:** the prompt (or its file path), the target state you checked, and
one line: 要我派发吗？派发到哪里？
