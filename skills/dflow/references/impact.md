# 影响面 (impact)

**Find what a change breaks somewhere else, and prove the one fact it is safe
because of by running real code.** From pstack `blast-radius`. Principles:
真实证据, 通用解, 以现状为准.

Listing callers is not the job; grep does that in a second. The job is the
breakage grep will not show. A writeup that sounds right is worth nothing on
its own: it reads the same whether or not it is true.

Use it when the user asks ("影响面", "会影响什么", "这个改动安全吗"), when
reviewing code, and when `SKILL.md` **After any change** step 3 triggers it.
Read-only unless the user asked for the fix too.

## Evidence levels

Take each fact the change's safety depends on as far down this list as is
cheap, and say where it stopped.

1. 说了: you said so. Worth nothing alone.
2. 指到代码行: a real `path:line`, or the library's own source.
3. 推演排除: you walked the failure step by step and it cannot reach.
4. 跑过: a script or test that calls the real code and fails loudly if you
   are wrong.
5. 真实应用复现: reproduced in the running app.

Level 4 is usually one small script in the scratch directory that imports the
same code the app ships and calls the exact function in question.

## Steps

1. **Say what the change actually does.** The diff, the symbols it adds,
   changes, and deletes, and what now behaves differently, including what the
   diff does not spell out. Read history with `git log -p`/`git blame` when
   the old behavior matters.
2. **Look where grep stops.** Language-agnostic checklist:
   - **Stored data**: files, saves, databases, caches, fixtures written by the
     old code. Can the new code read them? Can old code read what new code
     writes?
   - **Config and flags**: which combinations reach the changed path.
   - **Other readers**: another process, language, repo, tool, or external
     user reading the same data, output, or API.
   - **Timing and lifecycle**: async order, init and teardown, re-entry,
     retries.
   - **Indirect references**: names held as strings or paths (registries,
     reflection, scene or resource files, routes, templates) that a symbol
     search misses. Search the string forms too.
   A search that finds nothing is still an answer; write the command.
3. **Find the one fact it is safe because of.** Most risky-looking changes are
   safe because of one fact ("旧存档里不存在这个字段", "这个函数只在启动时调用
   一次"). If it holds, most risks clear at once. Spend the time here, not on a
   long list of maybes.
4. **Prove that fact.** Write the script or test, run it, and keep the output.
   Proving some other fact does not count. If it cannot be run here, say which
   level it reached and call the change 未证明.
5. **Be honest about each risk.** Give a real chance and a real cost. Keep
   confirmed risks; list checked-and-cleared ones separately. Cite a real
   `path:line`; never invent a caller or an API.

For an interface change inside one repo with no external users, the fix is to
migrate every caller in the same change and delete the old shape, not to keep
a compatibility layer. Say so when external users exist.

**Reply:**

```text
**影响面**：<安全 / 有风险 / 未证明> — <一句话>
- 改动实际做了什么：<含 diff 没写出来的部分>
- 安全依据：<那一个事实>（<证据等级>）<脚本路径和输出要点；做不到就写停在哪一级>
- 风险：<位置 → 怎么坏 → 可能性 / 代价 → 怎么查；最多 5 条；没有就写无>
- 已排除：<查过什么、为什么没问题，含搜索命令>
- 合并前最便宜的检查：<一条命令或测试>
```
