#!/usr/bin/env python3
"""Merge Claude Code or Codex transcripts into one tool-call timeline for a closeout or 复盘.

Usage: python3 -I timeline.py [--danger | --say] <session-id or transcript.jsonl>...
A session id is looked up as ~/.claude/projects/*/<id>.jsonl (override the root with
DFLOW_TRANSCRIPTS), together with its subagents' transcripts in <id>/subagents/*.jsonl,
which are labelled agent-<id> in column 2. Failing that, it is a Codex thread id, looked up
as ~/.codex/sessions/*/*/*/rollout-*-<id>.jsonl (override with DFLOW_CODEX_SESSIONS), together
with every rollout whose parent_thread_id leads back to it (subagents, labelled
agent-<last 8 of id>; a Codex thread is labelled by the last 8 characters of its id, since its
first ones encode the start time; the parent history a forked subagent starts with is skipped). Codex shell
calls (exec_command) are labelled Bash like Claude's, so the DANGER check covers both.
Output, one line per tool call, sorted by time:
  <ts>\t<session[:8]>\t<tool>\t<command or path>\t<ok|error>\t<first line of result>
--say keeps whole commands (up to 20000 characters; a cut one ends in "…[截断，原文 N 字]")
and also prints what was said, so a reviewer can check the stated reasons and claims
against the calls: the assistant's text as tool "assistant", and what the user typed as tool
"user" (injected meta messages and tool results left out; a background-task notice is
"notice", as is a Codex turn the user did not start, such as a goal continuation; in a
subagent transcript the message is the coordinator's "prompt"), the text
in column 4, "-" in column 5. With --say, column 6 holds the first 400 characters of each
result instead of its first line, since a check's verdict is often not on its first line.
A call that matches an action the unattended playbook forbids is marked DANGER in column 5.
--danger prints only those rows and exits 1 when there are any (use it instead of grepping,
since a command that mentions the word DANGER would match a grep).
A session whose transcript is missing prints "未核实\t<id>" on stderr; exit 2 if any is missing.
Read-only.
"""
import glob
import json
import os
import re
import sys

# A git subcommand the unattended playbook forbids, right after `git` and its global options.
DANGER = re.compile(
    r"\bgit(?:\s+-[Cc]\s+\S+|\s+--?[\w-]+(?:=\S+)?)*\s+"
    r"(push|merge(?!-base|-tree|-file)|rebase|reset|clean|cherry-pick|switch(?!\s+-[cC]\s+(?:dflow/|worktree-agent-|\x22?\$\(git branch --show-current\)))|checkout\s+-[bB](?!\s+dflow/)|commit\s+[^|;&]*--amend|"
    r"stash(?!\s+list)|tag\s+\w+|branch\s+-[dDmMfc]|worktree\s+(?:add|remove|move|prune))\b")


# `parallel.sh land|cleanup` is the one sanctioned use of cherry-pick, worktree removal,
# and branch deletion; drop that fragment before scanning so the rest of the line still counts.
SANCTIONED = re.compile(r"(\S*/)?parallel\.sh\s+(land|cleanup)\s+[a-z0-9-]+(\s+[A-Za-z0-9_.-]+)?")


def codex_meta(path):
    """The session_meta payload of a Codex rollout, or None for any other file."""
    try:
        with open(path, encoding="utf-8") as f:
            e = json.loads(f.readline())
    except (OSError, ValueError):
        return None
    return e.get("payload") if isinstance(e, dict) and e.get("type") == "session_meta" else None


def codex_children(root, tid, since):
    """Rollouts under root whose parent_thread_id is tid, then theirs, in file-name order."""
    found, todo = [], [tid]
    files = [f for f in glob.glob(os.path.join(root, "*", "*", "*", "rollout-*.jsonl"))
             if os.path.basename(f) >= since]
    parents = {}
    for f in files:
        m = codex_meta(f) or {}
        if m.get("parent_thread_id"):
            parents.setdefault(m["parent_thread_id"], []).append((f, m.get("id", "")))
    while todo:
        for f, cid in sorted(parents.get(todo.pop(), [])):
            found.append(f)
            todo.append(cid)
    return found


def locate(arg):
    """Transcript paths for a .jsonl path or a session id (plus its subagents)."""
    if arg.endswith(".jsonl") and os.path.exists(arg):
        return [arg]
    root = os.environ.get("DFLOW_TRANSCRIPTS", os.path.expanduser("~/.claude/projects"))
    hits = glob.glob(os.path.join(root, "*", arg + ".jsonl"))
    if hits:
        subs = sorted(glob.glob(os.path.join(hits[0][:-6], "subagents", "*.jsonl")))
        return hits[:1] + subs
    croot = os.environ.get("DFLOW_CODEX_SESSIONS", os.path.expanduser("~/.codex/sessions"))
    hits = sorted(glob.glob(os.path.join(croot, "*", "*", "*", "rollout-*-" + arg + ".jsonl")))
    if not hits:
        return []
    return hits[:1] + codex_children(croot, arg, os.path.basename(hits[0])[:len("rollout-2026-01-01")])


def one_line(v, n=160):
    if isinstance(v, list):
        v = " ".join(b.get("text", "") for b in v if isinstance(b, dict))
    s = str(v).strip().replace("\t", " ")
    return (s.splitlines() or [""])[0][:n]


def text_of(v):
    if isinstance(v, list):
        return " ".join(b.get("text", "") for b in v if isinstance(b, dict))
    return str(v)


def flat(v, n=1500):
    """The whole value on one line: newlines become ' ⏎ ', so later lines of a command stay visible."""
    s = str(v).strip().replace("\t", " ")
    s = " ⏎ ".join(l.strip() for l in s.splitlines() if l.strip())
    return s if len(s) <= n else s[:n] + " …[截断，原文 %d 字]" % len(s)


def describe(name, inp, n=1500):
    for k in ("command", "file_path", "path", "pattern", "skill", "url", "query"):
        if k in inp:
            return flat(inp[k], n)
    return flat(json.dumps(inp, ensure_ascii=False), n)


def said(e, content):
    """(tool, text) rows for the assistant's text blocks or a message the user typed."""
    if e.get("type") == "assistant" and isinstance(content, list):
        return [("assistant", b.get("text", "")) for b in content
                if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip()]
    if e.get("type") == "user" and not e.get("isMeta") and not e.get("isCompactSummary"):
        if isinstance(content, str):
            return [("user", content)] if content.strip() else []
        if isinstance(content, list) and not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            text = " ".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
            return [("user", text)] if text.strip() else []
    return []


# Context Codex injects as user messages; not something the user typed.
CODEX_INJECTED = ("<environment_context>", "<user_instructions>", "<permissions", "# AGENTS.md",
                  "<skills_instructions>", "<collaboration_mode>", "<personality", "<skill>")


# Messages Codex itself sends in the user role: a goal continuation, a subagent finishing, an interrupt.
CODEX_NOTICES = ("<codex_internal_context", "<subagent_notification>", "<turn_aborted>")


def codex_text(content):
    return " ".join(b.get("text", "") for b in content or [] if isinstance(b, dict)
                    and b.get("type") in ("input_text", "output_text", "text"))


def codex_status(output):
    """(ok|error, result text) from a Codex tool output's header and body."""
    out = output if isinstance(output, str) else json.dumps(output, ensure_ascii=False)
    m = re.search(r"^(?:Process exited with code|Exit code:) (-?\d+)\s*$", out, re.M)
    body = out.split("\nOutput:\n", 1)[1] if "\nOutput:\n" in out else out
    return ("error" if m and m.group(1) != "0" else "ok"), body


def codex_describe(name, args, n):
    if name == "apply_patch":
        files = re.findall(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", str(args), re.M)
        return flat(" ".join(files) or str(args), n)
    if isinstance(args, dict):
        for k in ("cmd", "command", "path", "message", "objective", "target", "targets", "query"):
            if k in args:
                v = args[k]
                return flat(" ".join(v) if isinstance(v, list) and k in ("cmd", "command") else v, n)
        return flat(json.dumps(args, ensure_ascii=False), n)
    return flat(args, n)


def codex_rows(path, meta, say):
    calls, out = {}, []
    sub = meta.get("thread_source") == "subagent" or bool(meta.get("parent_thread_id"))
    # Codex ids are time-ordered (UUIDv7): threads started within about a minute share the first
    # eight characters, so label them by the random tail instead.
    tid = str(meta.get("id", os.path.basename(path)))
    sid = ("agent-" if sub else "") + tid[-8:]
    start = meta.get("subagent_history_start_ordinal", 0) if sub else 0
    first_user = True
    for line in open(path, encoding="utf-8"):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not isinstance(e, dict) or e.get("ordinal", start) < start:
            continue  # a forked subagent's copy of its parent's history
        p, ts = e.get("payload") or {}, e.get("timestamp", "")
        kind = p.get("type")
        if e.get("type") == "event_msg" and kind == "task_started" and say:
            trig = (p.get("turn_attribution") or {}).get("turn_trigger", "user")
            if trig != "user":
                out.append([ts, sid, "notice", "turn started by " + trig, "-", ""])
        if e.get("type") != "response_item":
            continue
        if kind == "message" and say:
            role, text = p.get("role"), codex_text(p.get("content"))
            if not text.strip() or role not in ("user", "assistant"):
                continue
            if role == "user":
                if text.lstrip().startswith(CODEX_INJECTED):
                    continue
                who = "notice" if text.lstrip().startswith(CODEX_NOTICES) else \
                    ("prompt" if sub and first_user else "user")
                first_user = False
            else:
                who = "assistant"
            out.append([ts, sid, who, flat(text, 8000), "-", ""])
        elif kind in ("function_call", "custom_tool_call"):
            name = p.get("name", "")
            args = p.get("input", "")
            if kind == "function_call":
                try:
                    args = json.loads(p.get("arguments") or "{}")
                except ValueError:
                    args = p.get("arguments", "")
            label = "Bash" if name in ("exec_command", "shell", "local_shell") else name
            desc = codex_describe(name, args, 20000 if say else 1500)
            full = codex_describe(name, args, 10 ** 9) if label == "Bash" else ""
            calls[p.get("call_id")] = [ts, sid, label, desc, "pending", "", full]
            out.append(calls[p.get("call_id")])
        elif kind in ("function_call_output", "custom_tool_call_output") and p.get("call_id") in calls:
            c = calls[p["call_id"]]
            c[4], body = codex_status(p.get("output", ""))
            c[5] = flat(body, 400) if say else one_line(body)
    return out


def rows(path, say=False):
    meta = codex_meta(path)
    if meta is not None:
        out = codex_rows(path, meta, say)
        return mark(out)
    calls, out = {}, []
    for line in open(path, encoding="utf-8"):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        # Only the conversation's own turns; other entries (api-request-blob and the like)
        # carry copies of earlier messages without a timestamp and would duplicate calls.
        if not isinstance(e, dict) or e.get("type") not in ("assistant", "user"):
            continue
        content = (e.get("message") or {}).get("content")
        name = os.path.basename(path)[:-6]
        sid = name if name.startswith("agent-") else (e.get("sessionId") or name)[:8]
        if say:
            for who, text in said(e, content):
                if who == "user" and text.lstrip().startswith("<task-notification>"):
                    who = "notice"
                elif who == "user" and sid.startswith("agent-"):
                    who = "prompt"
                out.append([e.get("timestamp", ""), sid, who, flat(text, 8000), "-", ""])
        if not isinstance(content, list):
            continue
        for b in content:
            if b.get("type") == "tool_use":
                inp = b.get("input") or {}
                calls[b["id"]] = [e.get("timestamp", ""), sid, b.get("name", ""),
                                  describe(b.get("name", ""), inp, 20000 if say else 1500), "pending", "",
                                  str(inp.get("command", ""))]
                out.append(calls[b["id"]])
            elif b.get("type") == "tool_result" and b.get("tool_use_id") in calls:
                c = calls[b["tool_use_id"]]
                c[4] = "error" if b.get("is_error") else "ok"
                c[5] = flat(text_of(b.get("content", "")), 400) if say else one_line(b.get("content", ""))
    return mark(out)


def mark(out):
    for c in out:
        full = c.pop() if len(c) == 7 else ""
        if c[2] == "Bash" and DANGER.search(SANCTIONED.sub(" ", full)):  # full command, minus the sanctioned call
            c[4] = "DANGER " + c[4]
    return out


def main(args):
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    danger = args[:1] == ["--danger"]
    say = args[:1] == ["--say"]
    if danger or say:
        args = args[1:]
    allrows, missing = [], False
    for a in args:
        paths = locate(a)
        if not paths:
            print("未核实\t" + a, file=sys.stderr)
            missing = True
            continue
        for p in paths:
            allrows += rows(p, say)
    flagged = False
    for r in sorted(allrows, key=lambda r: r[0]):
        if danger and not r[4].startswith("DANGER"):
            continue
        flagged = flagged or r[4].startswith("DANGER")
        print("\t".join(r))
    if missing:
        return 2
    return 1 if danger and flagged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
