# 解释数字 (explain the number)

Before you trust, report, or act on a measured number:

- Name what bounds it (a core, a lock, the disk, the network, the load
  generator), from a profile or counters, not from reading code. If you cannot
  say why it is not twice as good, you do not know what you measured.
- List what else it could be measuring and rule each out: errors, skipped or
  cached work, code that never ran, an untuned side, noise, a piece too small
  to matter end to end.
- Keep run count, spread, and limiter with the number. For performance, run
  `references/benchmark-checklist.md`.
