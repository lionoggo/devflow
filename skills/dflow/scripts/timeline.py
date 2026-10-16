#!/usr/bin/env python3
"""Merge Claude Code transcripts into one tool-call timeline for an unattended-run closeout.

Usage: python3 -I timeline.py [--danger | --say] <session-id or transcript.jsonl>...
A session id is looked up as ~/.claude/projects/*/<id>.jsonl (override the root with
DFLOW_TRANSCRIPTS), together with its subagents' transcripts in <id>/subagents/*.jsonl,
which are labelled agent-<id> in column 2. Output, one line per tool call, sorted by time:
  <ts>\t<session[:8]>\t<tool>\t<command or path>\t<ok|error>\t<first line of result>
--say also prints what was said, so a reviewer can check the stated reasons and claims
against the calls: the assistant's text as tool "assistant", and what the user typed as tool
"user" (injected meta messages and tool results left out; a background-task notice is
"notice", and in a subagent transcript the message is the coordinator's "prompt"), the text
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


def locate(arg):
    """Transcript paths for a .jsonl path or a session id (plus its subagents)."""
    if arg.endswith(".jsonl") and os.path.exists(arg):
        return [arg]
    root = os.environ.get("DFLOW_TRANSCRIPTS", os.path.expanduser("~/.claude/projects"))
    hits = glob.glob(os.path.join(root, "*", arg + ".jsonl"))
    if not hits:
        return []
    subs = sorted(glob.glob(os.path.join(hits[0][:-6], "subagents", "*.jsonl")))
    return hits[:1] + subs


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
    return " ⏎ ".join(l.strip() for l in s.splitlines() if l.strip())[:n]


def describe(name, inp):
    for k in ("command", "file_path", "path", "pattern", "skill", "url", "query"):
        if k in inp:
            return flat(inp[k])
    return flat(json.dumps(inp, ensure_ascii=False))


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


def rows(path, say=False):
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
                out.append([e.get("timestamp", ""), sid, who, flat(text), "-", ""])
        if not isinstance(content, list):
            continue
        for b in content:
            if b.get("type") == "tool_use":
                inp = b.get("input") or {}
                calls[b["id"]] = [e.get("timestamp", ""), sid, b.get("name", ""),
                                  describe(b.get("name", ""), inp), "pending", "",
                                  str(inp.get("command", ""))]
                out.append(calls[b["id"]])
            elif b.get("type") == "tool_result" and b.get("tool_use_id") in calls:
                c = calls[b["tool_use_id"]]
                c[4] = "error" if b.get("is_error") else "ok"
                c[5] = flat(text_of(b.get("content", "")), 400) if say else one_line(b.get("content", ""))
    for c in out:
        if c[2] == "Bash" and DANGER.search(SANCTIONED.sub(" ", c.pop())):  # full command, minus the sanctioned call
            c[4] = "DANGER " + c[4]
        elif len(c) == 7:
            c.pop()
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
