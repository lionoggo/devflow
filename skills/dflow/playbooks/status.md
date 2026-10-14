### 进展 (status)

**Catch the user up: what came of each thing they asked for, and what waits
on them. Read-only.** From pstack `ketchup`. Principles: 以现状为准, 真实证据.

1. Collect, without changing anything: this conversation since the user's
   last message, subagent and background results, `git log` and
   `git status`, todo state, and any run log (`.dflow/*.tsv`). Re-check each
   number you will show against its source.
2. An item for the user is a decision or step only they can take: a product
   choice, an approval, an outside or irreversible action, access you lack.
   Work you can still do yourself is not one; say it in one line instead.
3. Write it the way one person catches up another: what changed for the
   user, not how you did it. Leave out hashes, paths, and commands unless the
   user needs one to act. Under about 150 Chinese characters plus the list.
   No diagram unless asked.

**Reply:**

```text
<有 N 件事需要你 / 没有需要你的事>。
- <要求的事>：<结果>（<完成 / 进行中 / 失败 / 未验证>）
- 我还能继续做的：<一行；没有就省略>
需要你定：
1. <决定> — 推荐 <选项>，因为 <理由>。
   不回复的话：<会发生什么>
```
