---
name: devflow-debug
description: "Investigate an observed bug or unexpected behavior from symptom to evidence-backed cause, and fix it when the user asked for a fix and the cause and scope are clear. Use when the user reports a bug, asks to debug, reproduce, find the root cause, triage logs, or compare expected with actual behavior. Do not use for fuzzy improvements (devflow-plan) or acceptance of finished work (devflow-verify)."
---

# Devflow Debug

- Fix only the problem itself; don't add unrequested features or defensive
  code. When the cause is data, configuration, or environment, fix that or
  give the recovery step instead of changing code.
- After a fix, rerun the reproduction and the relevant tests and report the
  results; if they cannot run, say so.
- When the user only asked for the cause, don't edit files.
- For a baseline use `git show <rev>:<path>`, never checkout, reset, stash, or
  clean.

Reply conclusion first:

```text
**结论**：<原因已确认 / 未确认 / 受阻> — <the cause in one sentence>
- 证据：<minimal decisive evidence>
- 修复：<change made | proposed change | recovery step>
- 验证：<reproduction result; tests run and their results, or why they were not run>
- 改动的已有测试：<each existing test whose expected behavior changed → why; omit if none>
```
