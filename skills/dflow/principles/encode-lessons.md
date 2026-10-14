# 结构化教训 (encode lessons in structure)

When the same correction appears a second time, or you write the same
instruction twice, fix it at the highest level that works:

1. Remove it with structure: one owner per state, one supported way, delete
   the old way an agent would copy.
2. Make the bad state fail: a type, lint, script, hook, or CI check whose error
   names what to do instead.
3. Test the behavior.
4. Only for judgment calls: a written rule, with an example of the failure.

Prove a new check fails on a real past mistake. If the fix is structural, keep
only the structural fix; the instruction was the symptom. See
`playbooks/tune.md`.
