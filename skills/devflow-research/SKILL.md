---
name: devflow-research
description: "Explain how existing code works — a whole project's architecture or one feature's implementation principle — with evidence-backed conclusions, choosing between a direct answer, a personal note, or a shareable research document with diagrams, worked examples, and optional industry comparison. Use when the user asks 怎么实现的, 实现原理, 调研（现有代码）, 现有项目的架构, how a specific behavior is decided or handled in the code (X 是怎么选/怎么处理/怎么工作的), how does X work, walk me through X, or wants a research write-up; the target repository need not be one that will be modified. Do not use for observed failures or unexpected behavior (devflow-debug), choosing a direction or planning a change (devflow-plan), or locating a single file or symbol."
---

# Devflow Research

Explain existing code. Read-only: never edit project code. The user's explicit
instructions override the defaults below.

## Rules

- Tie key conclusions to code, tests, or docs (`path:line`). Take line numbers
  only from numbered output (Read tool, `grep -n`, `nl -ba`); if you only saw
  unnumbered output, cite the file and symbol instead. Mark inferences `[推测]`
  with how to confirm them.
- Read the key code on the main path yourself; subagent findings are leads to
  verify.
- Explain why: for each key design, the problem it solves and its cost.
- Keep each claim's conditions (only when configured, fallback, default vs
  opt-in).
- Label examples 实际演练 (run in this session) or 推演 (derived from code or
  tests); never present predicted output as observed.
- When behavior depends on prompts, config, or environment, confirm it in a
  real run artifact (logs, workspace, data) and label it 实际演练.
- Answer the question asked; mention adjacent findings briefly.
- Don't install dependencies or run commands that create environments
  (`uv run`, `pip install`, `npm install`…); run tests only if the tools
  already exist.
- If the question turns into "why is this broken" (`devflow-debug`) or "what
  should we change" (`devflow-plan`), say so and stop at positioning.

## Output

Pick the lightest form that answers the question; say which one when writing a
file:

- **Direct answer** (default): a few paragraphs with the decisive code
  locations; no file.
- **Note / document**: when the user asks for one (整理、记录、写成文档) or the
  chain is too long for a reply. Default path `docs/research/<topic>.md` in the
  user's own repository (cwd or ask for third-party checkouts); never stage or
  commit it. Use `references/report-template.md` as a guide, not a quota;
  record the commit hash. For a document meant for others, re-check key claims
  against the code before delivering. If another model is available, have it
  review only for factual errors and wrong citations; verify each finding
  (including that the code path is reachable) before editing, and stop after
  a clean round.

Add diagrams (`references/diagrams.md`) when they help. Do an industry
comparison (`references/industry-comparison.md`) or an HTML demo
(`references/html-demo.md`) only when the user asks; otherwise offer it in one
line. Reply in
Simplified Chinese; for a file, end with its path and the most important
unverified item.
