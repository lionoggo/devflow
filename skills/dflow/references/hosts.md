# 宿主对照 (hosts)

Every playbook runs in Claude Code and in Codex. The playbooks name the
Claude Code tool; in Codex use the right-hand column. A row marked
"measured" was observed on Codex CLI 0.162–0.163 (2026-10-16); recheck it
when a Codex update changes behavior.

| Need | Claude Code | Codex |
|---|---|---|
| Session id (lease, `start` rows) | `$CLAUDE_CODE_SESSION_ID` | `$CODEX_THREAD_ID` |
| Transcripts (`scripts/timeline.py` reads both) | `~/.claude/projects/*/<id>.jsonl`, subagents in `<id>/subagents/` | `~/.codex/sessions/*/*/*/rollout-*-<id>.jsonl`; a subagent's rollout names its `parent_thread_id` |
| The route as a todo list | TodoWrite, or TaskCreate via ToolSearch | `update_plan` when the session has it; otherwise the route line |
| Read-only explorer, fresh verifier | Agent, Explore type, model `sonnet` | `spawn_agent` with `fork_context: false` and `reasoning_effort: "medium"`. It has your sandbox, not fewer tools, so its prompt says "只读，不改文件" |
| Worker in its own worktree (并行) | Agent with `isolation: "worktree"`, `run_in_background: true` | `scripts/parallel.sh worktree <slug> <id>` first, then `spawn_agent` with the brief and that path as its working directory |
| A worker finished | it wakes you | `wait_agent` on the running workers (up to 1 hour per call) |
| Resume a worker | SendMessage | `send_input`; `resume_agent` first if it was closed |
| Wait for a long command | background Bash, or Monitor | run it in the foreground with a long `timeout_ms`, or hand it to a worker and `wait_agent`; never poll with sleeps |
| Repeat rounds (无人值守) | Skill `loop` with no interval | `create_goal`; each goal continuation is a Round. `update_goal` with `complete` (or `blocked`) at Close, `paused` at Pause. Measured: continuation runs only in an interactive session (app, IDE, TUI); `codex exec` aborts it after the first turn |
| Notify the user | PushNotification | `scripts/notify.sh <message>` (a desktop notice, not a phone push) |
| Cross-model review (allow 20 minutes) | `codex exec -s read-only`, prompt on stdin or with `</dev/null` | `scripts/review.sh start <prompt file> <out file>`, then `review.sh wait <out file>` until it prints `ended` (it runs `claude -p --permission-mode plan` in its own session; each wait returns within 50 seconds, so no call blocks for minutes); needs network. Call it through the shell tool, never the node REPL or another MCP tool: measured, `claude` there reports "Not logged in" |
| Project skills | `.claude/skills/` | `.agents/skills/` or `.codex/skills/` (measured: `.claude/skills/` is not read) |
| Global rule files (ask first) | `~/.claude/CLAUDE.md`, `~/.claude/settings.json` | `~/.codex/AGENTS.md`, `~/.codex/config.toml` |
| Never stop for a permission prompt (无人值守) | bypass permissions mode | approval `never` and a sandbox that can write the repo and `.git` and reach the network for review (`danger-full-access`, or `workspace-write` with network on) |

Measured facts behind the Codex column:
- A goal continuation starts a turn with trigger `goal` and a
  `<codex_internal_context source="goal">` message; `timeline.py --say` shows
  both as `notice`, never as something the user said.
- `spawn_agent` has no worktree, read-only, or background option; the child
  runs in your sandbox and cwd until told otherwise. A child started with
  `fork_context` begins with a copy of your history, which `timeline.py`
  skips.
- `exec_command` blocks until the command ends or its `timeout_ms` passes.
  When the call ends, processes it started in the background die with it,
  `nohup … &` included; only a new session survives, which is how
  `run-state.sh caffeinate` starts caffeinate and `review.sh start` the
  reviewer. The default `timeout_ms` is 10 seconds, so a long command needs
  an explicit one.
- The Codex model keeps a single call under about 60 seconds even when told
  to wait 20 minutes, so a reviewer run in the foreground is cut off and
  yields 未审查; that is why the review goes through `review.sh`.
