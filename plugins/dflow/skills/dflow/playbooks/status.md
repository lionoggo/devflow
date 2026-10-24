### 进展 (status)

**Catch the user up: what came of each thing they asked for, and what waits
on them. Read-only.** From pstack `ketchup`. Principles: 以现状为准, 真实证据.

1. Collect, without changing anything: this conversation since the user's
   last message, subagent and background results, `git log` and
   `git status`, todo state, and any run log (`.dflow/*.tsv`). Re-check each
   number you will show against its source. A 多线 run: start from
   `scripts/lines.sh status <slug> --print` (it prints the board and writes
   nothing: no `status.md`, no snapshot, no lock), then check it live (each
   line's branch in `git log`, `scripts/agent.sh peek <slug> <id> <attempt>`
   for headless lines, receipts on disk); the board is a cache, not the
   truth. Never call `agent.sh wait` or `lines.sh status` without `--print`
   here: `wait` can stop a worker past its limit, and `status` rewrites the
   run's files.
2. An item for the user is a decision or step only they can take: a product
   choice, an approval, an outside or irreversible action, access you lack.
   Work you can still do yourself is not one, even if you would like a go
   ahead: say it in one line under 我还能继续做的, never as a decision.
   For each item collect the call, your pick, what it changes for the user,
   the evidence for the pick, and its risk (a low one too, in a phrase).
3. Write it the way one person catches up another: what changed for the
   user, not how you did it. Leave out hashes, paths, and commands unless the
   user needs one to act. What happened stays under about 150 Chinese
   characters; the decisions take the room they need, and no item is cut or
   shrunk to fit. Items sharing one call: the call and pick once, then one
   line per item, riskiest first. Say what waiting costs only when it is more
   than a delay (a deadline, lost data). No diagram unless asked.

**Reply:**

```text
<有 N 件事需要你 / 没有需要你的事>。
- <要求的事>：<结果>（<完成 / 进行中 / 失败 / 未验证>）
- 我还能继续做的：<一行；没有就省略>
需要你定：
1. <决定>。推荐 <选项>。影响：<对你有什么变化>。依据：<证据>。风险：<一句>。
   等待的代价：<只在有截止日期或会丢数据时写>
```
