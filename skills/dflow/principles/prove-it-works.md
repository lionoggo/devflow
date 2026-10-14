# 真实证据 (prove it works)

Check the real thing, not a proxy, a self-report, or "it compiles".

- A user-visible or runnable claim needs one observation on the real usage
  path: the real command, request, page, or stored value. Unit and static
  checks support it; they do not prove it.
- Read the actual value, not a cached or derived one. When verification fails,
  suspect the observation method before the system.
- Prefer a rerunnable script over a one-time look; keep its output as the
  evidence.
- Not run means "未验证", with the reason. Inconclusive is not a pass.
- For a critical constraint, the evidence must tell a correct implementation
  apart from a cheaper one that breaks it but looks the same.

You skipped this when "完成" has no command output, screenshot, or stored value
behind it.
