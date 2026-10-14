#!/usr/bin/env python3
"""Merge Claude Code transcripts into one tool-call timeline for an unattended-run closeout.

Usage: python3 -I timeline.py [--danger] <session-id or transcript.jsonl>...
A session id is looked up as ~/.claude/projects/*/<id>.jsonl (override the root with
DFLOW_TRANSCRIPTS), together with its subagents' transcripts in <id>/subagents/*.jsonl,
which are labelled agent-<id> in column 2. Output, one line per tool call, sorted by time:
  <ts>\t<session[:8]>\t<tool>\t<command or path>\t<ok|error>\t<first line of result>
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
    r"(push|merge|rebase|reset|clean|cherry-pick|switch(?!\s+-[cC]\s+(?:dflow/|worktree-agent-|\x22?\$\(git branch --show-current\)))|checkout\s+-[bB](?!\s+dflow/)|commit\s+[^|;&]*--amend|"
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


def flat(v, n=1500):
    """The whole value on one line: newlines become ' ⏎ ', so later lines of a command stay visible."""
    s = str(v).strip().replace("\t", " ")
    return " ⏎ ".join(l.strip() for l in s.splitlines() if l.strip())[:n]


def describe(name, inp):
    for k in ("command", "file_path", "path", "pattern", "skill", "url", "query"):
        if k in inp:
            return flat(inp[k])
    return flat(json.dumps(inp, ensure_ascii=False))


def rows(path):
    calls, out = {}, []
    for line in open(path, encoding="utf-8"):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not isinstance(e, dict):
            continue
        content = (e.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        name = os.path.basename(path)[:-6]
        sid = name if name.startswith("agent-") else (e.get("sessionId") or name)[:8]
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
                c[5] = one_line(b.get("content", ""))
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
    if danger:
        args = args[1:]
    allrows, missing = [], False
    for a in args:
        paths = locate(a)
        if not paths:
            print("未核实\t" + a, file=sys.stderr)
            missing = True
            continue
        for p in paths:
            allrows += rows(p)
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
