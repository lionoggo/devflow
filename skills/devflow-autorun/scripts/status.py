#!/usr/bin/env python3
"""Plan-level progress view for devflow-autorun runs.

Usage:
  status.py <root>                      regenerate .devflow/status.json and status.html
  status.py <root> --notify             same, then print notification events (JSON) and advance
                                        .devflow/notify-state.json
  status.py <root> --summary            same as plain, then print a short plain-text summary
  status.py <root> register <slug> --dry-run
  status.py <root> register <slug> --apply --expect <sha256|none>

Sources (read only): .devflow/roadmap.json, .devflow/roadmap.tsv, .devflow/<slug>.{md,tsv,running}.
Every mode holds an exclusive lock on .devflow/status.lock for the whole run.
Standard library only; run with python3 -I.
"""
import difflib
import fcntl
import hashlib
import html
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

CONTRACT_TITLE = "# 自动运行契约："
HEADER = ["ts", "phase", "decision", "why", "evidence", "result"]
END_STATES = ("完成", "部分完成", "受阻")
STALE_SECONDS = 45 * 60
COST_TIMEOUT = float(os.environ.get("DEVFLOW_COST_TIMEOUT", "10"))  # override for tests only
ACTIONS = ("已处理", "已决定", "已查看", "撤回")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


# ---------- small helpers ----------

def sha256_file(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except FileNotFoundError:
        return "none"


def write_atomic(path, text):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-", suffix=os.path.basename(path))
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def load_json(path):
    """Return (data, error). Missing file -> (None, None)."""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f), None
    except FileNotFoundError:
        return None, None
    except (OSError, ValueError) as e:
        return None, str(e)


def uncell(v):
    """Undo log.sh's spreadsheet guard: a leading ' before = + - @."""
    if len(v) >= 2 and v[0] == "'" and v[1] in "=+-@":
        return v[1:]
    return v


def read_tsv(path):
    """Rows as dicts; header lines (also repeated ones) are skipped. None when the file is missing."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return None
    rows = []
    for line in lines:
        cells = line.split("\t")
        if cells[:6] == HEADER or not line.strip():
            continue
        cells = (cells + [""] * 6)[:6]
        rows.append(dict(zip(HEADER, [uncell(c) for c in cells])))
    return rows


def parse_ts(ts):
    try:
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
    except ValueError:
        return None


def fmt_local(epoch):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(epoch)) if epoch else "—"


def fmt_cost(v):
    return f"${v:,.2f}"


# ---------- runs ----------

def contract_slugs(dv):
    out = []
    for name in sorted(os.listdir(dv)):
        if not name.endswith(".md"):
            continue
        try:
            with open(os.path.join(dv, name), encoding="utf-8") as f:
                first = f.readline()
        except OSError:
            continue
        if first.startswith(CONTRACT_TITLE):
            out.append(name[:-3])
    return out


def close_state(decision):
    word = re.split(r"[\s—]+", decision.strip(), maxsplit=1)[0] if decision.strip() else ""
    return word if word in END_STATES else "解析错误"


def scan_run(dv, slug, now):
    md = os.path.join(dv, slug + ".md")
    rows = read_tsv(os.path.join(dv, slug + ".tsv"))
    marker = os.path.join(dv, slug + ".running")
    running = os.path.exists(marker)
    closes = [r for r in (rows or []) if r["phase"] == "close"]
    last_ts = None
    for r in rows or []:
        t = parse_ts(r["ts"])
        if t:
            last_ts = t
    if running:
        ref = last_ts or os.path.getmtime(marker)
        status = "运行中·可能失联" if now - ref > STALE_SECONDS else "运行中"
    elif closes:
        status = close_state(closes[-1]["decision"])
    elif rows:
        status = "未收尾"
    else:
        status = "起草中"
    started = rows is not None or running
    progress = [r for r in (rows or []) if r["phase"] not in ("start", "close", "review")]
    if closes:
        condition = closes[-1]["result"]
    elif progress:
        condition = progress[-1]["result"]
    else:
        condition = ""
    decisions, events = [], []
    n = 0
    for r in rows or []:
        parked = "parked:" in r["decision"] or "parked:" in r["result"]
        if parked:
            n += 1
            reason = r["result"] if "parked:" in r["result"] else r["decision"]
            decisions.append({"id": f"{slug}/D{n}", "run": slug, "ts": r["ts"],
                              "text": f"{r['phase']} · {reason}" if r["phase"] else reason})
        low = (r["decision"] + " " + r["result"]).lower()
        if r["phase"] in ("start", "close") or parked or "受阻" in r["decision"] or "revert" in low or "撤回" in low:
            events.append({"ts": r["ts"], "phase": r["phase"], "decision": r["decision"],
                           "evidence": r["evidence"], "result": r["result"]})
    return {
        "id": slug, "status": status, "started": started, "running": running,
        "last_update": last_ts, "condition": condition, "decisions": decisions,
        "events": events, "close_ts": closes[-1]["ts"] if closes else None,
        "contract_sha256": sha256_file(md),
    }


# ---------- cost ----------

def run_cost(root, slug, run, meta, prev_runs):
    cmd = (meta or {}).get("cost_cmd")
    cap = (meta or {}).get("cost_cap")
    if not cmd:
        return {"state": "未统计", "value": None, "cap": cap}
    key = None
    if run["close_ts"] and not run["running"]:
        key = f"{run['contract_sha256']}|{run['close_ts']}|{cmd}"
        cached = ((prev_runs or {}).get(slug) or {}).get("cost") or {}
        if cached.get("key") == key and cached.get("state") == "ok":
            return dict(cached, cap=cap)
    try:
        p = subprocess.run(cmd, shell=True, cwd=root, capture_output=True, text=True, timeout=COST_TIMEOUT)
        out = p.stdout.strip().lstrip("$").replace(",", "")
        if p.returncode != 0:
            raise ValueError(f"exit {p.returncode}")
        value = float(out)
        return {"state": "ok", "value": value, "cap": cap, "key": key}
    except subprocess.TimeoutExpired:
        return {"state": "读取失败", "value": None, "cap": cap, "reason": "超时"}
    except (ValueError, OSError) as e:
        return {"state": "读取失败", "value": None, "cap": cap, "reason": str(e)[:80]}


def sum_costs(costs):
    known = [c["value"] for c in costs if c and c.get("state") == "ok"]
    unknown = sum(1 for c in costs if not c or c.get("state") != "ok")
    if not known:
        return {"value": None, "partial": unknown > 0, "label": "未统计"}
    total = sum(known)
    label = f"至少 {fmt_cost(total)}（部分未统计）" if unknown else fmt_cost(total)
    return {"value": total, "partial": unknown > 0, "label": label}


# ---------- answers ----------

def read_answers(dv):
    rows = read_tsv(os.path.join(dv, "roadmap.tsv")) or []
    latest = {}
    for r in rows:
        if r["phase"] != "user":
            continue
        parts = r["decision"].split(None, 1)
        if len(parts) != 2 or parts[1].strip() not in ACTIONS:
            continue
        latest[parts[0]] = {"action": parts[1].strip(), "text": r["why"], "ts": r["ts"]}
    return latest


def item_state(kind, answer):
    if not answer or answer["action"] == "撤回":
        return "open"
    if kind == "decision" and answer["action"] == "已决定":
        return "done"
    if kind == "check" and answer["action"] == "已处理":
        return "done"
    return "open"


# ---------- build ----------

def build(root, prev):
    dv = os.path.join(root, ".devflow")
    now = time.time()
    roadmap, rm_err = load_json(os.path.join(dv, "roadmap.json"))
    errors = []
    if rm_err:
        errors.append(f"登记表无法解析：{rm_err}")
    roadmap = roadmap or {"version": 1, "stages": [], "checks": [], "runs": {}}
    slugs = contract_slugs(dv) if os.path.isdir(dv) else []
    prev_runs = (prev or {}).get("runs") or {}
    runs = {s: scan_run(dv, s, now) for s in slugs}
    run_meta = roadmap.get("runs") or {}

    seen = {}
    for st in roadmap.get("stages") or []:
        for c in st.get("contracts") or []:
            for r in c.get("runs") or []:
                where = f"{st.get('id')}/{c.get('id')}"
                if r in seen:
                    errors.append(f"运行 {r} 重复登记：{seen[r]} 与 {where}")
                else:
                    seen[r] = where
                if r not in runs:
                    errors.append(f"登记的运行 {r} 在 .devflow/ 中找不到契约文件")

    for s, run in runs.items():
        run["cost"] = run_cost(root, s, run, run_meta.get(s), prev_runs)

    answers = read_answers(dv)
    items = []
    for s in slugs:
        for d in runs[s]["decisions"]:
            a = answers.get(d["id"])
            items.append(dict(d, kind="decision", state=item_state("decision", a), answer=a))
    for c in roadmap.get("checks") or []:
        a = answers.get(c.get("id"))
        items.append({"id": c.get("id"), "kind": "check", "text": c.get("text", ""),
                      "source": c.get("source", ""), "state": item_state("check", a), "answer": a})

    stages = []
    for st in roadmap.get("stages") or []:
        plan = st.get("plan") or ""
        sync = None
        if plan:
            cur = sha256_file(os.path.join(root, plan))
            if cur == "none":
                sync = "计划文件不存在"
            elif st.get("plan_sha256") and cur != st.get("plan_sha256"):
                sync = "登记待同步"
        contracts = []
        for c in st.get("contracts") or []:
            crun = [runs[r] for r in c.get("runs") or [] if r in runs]
            started = [r for r in crun if r["started"]]
            if not started:
                cstat = "未开始"
            elif any(r["running"] for r in started):
                cstat = "运行中"
            else:
                cstat = started[-1]["status"]
            contracts.append({"id": c.get("id"), "title": c.get("title") or c.get("id"),
                              "status": cstat, "runs": [r["id"] for r in crun],
                              "cost": sum_costs([r["cost"] for r in started])})
        any_started = any(runs[r]["started"] for c in st.get("contracts") or []
                          for r in c.get("runs") or [] if r in runs)
        if not plan or not contracts:
            sstat = "未开始"
        elif all(c["status"] == "完成" for c in contracts):
            sstat = "完成"
        elif any_started:
            sstat = "进行中"
        else:
            sstat = "未开始"
        stages.append({"id": st.get("id"), "title": st.get("title") or "", "plan": plan,
                       "sync": sync, "status": sstat, "contracts": contracts,
                       "cost": sum_costs([runs[r]["cost"] for c in st.get("contracts") or []
                                          for r in c.get("runs") or [] if r in runs and runs[r]["started"]])})

    unattached = [s for s in slugs if s not in seen]
    all_started = [r for r in runs.values() if r["started"]]
    return {
        "version": 1, "root": root, "generated_at": now,
        "stages": stages, "runs": runs, "unattached": unattached,
        "items": items, "errors": errors,
        "cost": sum_costs([r["cost"] for r in all_started]),
    }


# ---------- notify ----------

def business(state):
    return ({s: r["status"] for s, r in state["runs"].items()},
            {i["id"] for i in state["items"] if i["kind"] == "decision"},
            {i["id"] for i in state["items"] if i["kind"] == "decision" and i["state"] == "open"})


def notify(dv, state):
    path = os.path.join(dv, "notify-state.json")
    prev, err = load_json(path)
    time.sleep(float(os.environ.get("DEVFLOW_TEST_NOTIFY_PAUSE", "0")))  # widens the race window in tests only
    statuses, all_dec, open_dec = business(state)
    events = []
    if prev is not None and not err and isinstance(prev, dict):
        prev_runs = prev.get("runs") or {}
        prev_dec = set(prev.get("decisions") or [])
        for s, st in sorted(statuses.items()):
            if st in END_STATES and prev_runs.get(s) != st:
                events.append({"type": "run_end", "run": s, "status": st})
        for d in sorted(open_dec - prev_dec):
            item = next(i for i in state["items"] if i["id"] == d)
            events.append({"type": "new_decision", "id": d, "text": item["text"]})
        seen = prev_dec | all_dec
    else:
        seen = all_dec
    write_atomic(path, json.dumps({"runs": statuses, "decisions": sorted(seen)}, ensure_ascii=False, indent=1))
    msg = ""
    if events:
        parts = []
        for e in events:
            if e["type"] == "new_decision":
                parts.append(f"等你决定 {e['id']}")
            else:
                parts.append(f"{e['run']} {e['status']}")
        msg = "；".join(parts)
        if len(msg) > 190:
            msg = msg[:187] + "…"
    return {"events": events, "message": msg}


# ---------- summary ----------

def summary(state):
    open_items = [i for i in state["items"] if i["state"] == "open"]
    dec = [i for i in open_items if i["kind"] == "decision"]
    chk = [i for i in open_items if i["kind"] == "check"]
    lines = []
    if state["stages"]:
        cur = next((s for s in state["stages"] if s["status"] == "进行中"), None) or state["stages"][-1]
        done = sum(1 for c in cur["contracts"] if c["status"] == "完成")
        lines.append(f"方案：{cur['id']} {cur['title']} {cur['status']}，计划契约 {done}/{len(cur['contracts'])} 完成。")
    else:
        lines.append("方案：尚未登记（.devflow/roadmap.json 不存在或为空）。")
    running = [r for r in state["runs"].values() if r["running"]]
    lines.append("正在运行：" + ("；".join(f"{r['id']}（{r['status']}，最后更新 {fmt_local(r['last_update'])}）"
                                       for r in running) if running else "无"))
    closed = [r for r in state["runs"].values() if r["close_ts"]]
    if closed:
        last = max(closed, key=lambda r: r["close_ts"])
        lines.append(f"最近收尾：{last['id']} {last['status']}（{last['close_ts']}）")
    lines.append(f"等你处理：{len(dec)} 个决策、{len(chk)} 个人工项"
                 + ("：" + "、".join(i["id"] for i in (dec + chk)[:5]) + ("…" if len(dec) + len(chk) > 5 else "")
                    if dec or chk else ""))
    lines.append(f"花费：{state['cost']['label']}")
    if state["errors"]:
        lines.append(f"登记错误 {len(state['errors'])} 条，详见页面。")
    lines.append(f"页面：{os.path.join(state['root'], '.devflow', 'status.html')}")
    return "\n".join(lines[:8])


# ---------- html ----------

STATUS_CLASS = {"完成": "ok", "部分完成": "warn", "受阻": "bad", "运行中": "run", "运行中·可能失联": "bad",
                "未收尾": "warn", "起草中": "muted", "未开始": "muted", "进行中": "run", "解析错误": "bad"}

CSS = """
:root{--bg:#fbfaf8;--fg:#1d1d1b;--muted:#6b6a66;--line:#e4e2dc;--card:#fff;--ok:#2f7d4f;--warn:#a46a00;
--bad:#b3261e;--run:#2457a6;--chip:#f0eee9}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#171716;--fg:#ecebe7;--muted:#9a9891;
--line:#33322f;--card:#1f1f1d;--ok:#6cc08b;--warn:#e0a640;--bad:#f08a80;--run:#86aef0;--chip:#2a2a27}}
:root[data-theme=dark]{--bg:#171716;--fg:#ecebe7;--muted:#9a9891;--line:#33322f;--card:#1f1f1d;--ok:#6cc08b;
--warn:#e0a640;--bad:#f08a80;--run:#86aef0;--chip:#2a2a27}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);
font:15px/1.55 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif}
main{max-width:980px;margin:0 auto;padding:20px 16px 60px}
h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 10px}
.top{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
.top .line{font-size:16px}.muted{color:var(--muted)}.small{font-size:13px}
.s{display:inline-block;padding:0 8px;border-radius:999px;font-size:12.5px;background:var(--chip);white-space:nowrap}
.s.ok{color:var(--ok)}.s.warn{color:var(--warn)}.s.bad{color:var(--bad)}.s.run{color:var(--run)}.s.muted{color:var(--muted)}
.err{border-left:3px solid var(--bad);padding:6px 10px;margin:8px 0;background:var(--card)}
.item{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;padding:10px 12px;border:1px solid var(--line);
border-radius:8px;background:var(--card);margin:8px 0}
.item>.s{align-self:start;margin-top:2px}
.id{font-family:ui-monospace,Menlo,monospace;font-size:13px}.item .ctl{grid-column:2}
.chk{display:flex;gap:8px;align-items:flex-start;padding:5px 2px;border-top:1px solid var(--line)}
.chk:first-child{border-top:0}.chk .note{display:none;margin-top:4px}.chk input[type=checkbox]:checked~div .note{display:block}
.chk input[type=text]{width:100%;padding:4px 8px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--fg)}
.item input[type=text]{width:100%;padding:5px 8px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--fg)}
details{border:1px solid var(--line);border-radius:8px;background:var(--card);margin:8px 0}
details details{margin:6px 0 6px 12px;background:transparent}
summary{cursor:pointer;padding:8px 12px;list-style-position:inside}
.body{padding:2px 14px 10px}
table{border-collapse:collapse;width:100%;font-size:13px}td,th{border-top:1px solid var(--line);padding:4px 6px;
text-align:left;vertical-align:top;overflow-wrap:anywhere}
button{padding:6px 12px;border-radius:6px;border:1px solid var(--line);background:var(--chip);color:var(--fg);cursor:pointer}
textarea{width:100%;min-height:120px;font:12.5px ui-monospace,Menlo,monospace;padding:8px;border-radius:6px;
border:1px solid var(--line);background:var(--card);color:var(--fg)}
.nw{white-space:nowrap}
code{font-family:ui-monospace,Menlo,monospace;font-size:12.5px;overflow-wrap:anywhere}
"""

JS = r"""
let dirty=false;
document.addEventListener('input',()=>{dirty=true;document.getElementById('paused').hidden=false;});
setTimeout(function tick(){if(!dirty){location.reload();}else{setTimeout(tick,60000);}},60000);
function q(s){return "'"+String(s).replace(/'/g,"'\\''")+"'";}
function gen(){
  const said=[],cmds=[];
  document.querySelectorAll('[data-item]').forEach(el=>{
    const id=el.dataset.item,kind=el.dataset.kind;
    const box=el.querySelector('input[type=checkbox]'),txt=el.querySelector('input[type=text]');
    let action=null,text='';
    if(el.dataset.done==='1'){ if(box&&box.checked){action='撤回';} }
    else if(kind==='check'){ if(box&&box.checked){action='已处理';text=txt?txt.value.trim():'';} }
    else if(kind==='decision'){ if(txt&&txt.value.trim()){action='已决定';text=txt.value.trim();} }
    if(!action)return;
    said.push(id+' '+action+(text?'：'+text:''));
    cmds.push(LOG+' '+q(TSV)+' user '+q(id+' '+action)+' '+q(text)+" '' ''");
  });
  const out=document.getElementById('reply');
  out.value=said.length?(said.join('；')+'\n\n'+cmds.join('\n')+'\n'+REFRESH+'\n'):'（没有勾选或填写任何事项）';
  document.getElementById('replybox').hidden=false;
}
function copyReply(){
  const t=document.getElementById('reply');
  if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(t.value).then(()=>flash('已复制'),()=>sel());}
  else sel();
  function sel(){t.focus();t.select();try{document.execCommand('copy');flash('已复制');}catch(e){flash('请手动复制选中的文本');}}
}
function flash(m){const f=document.getElementById('flash');f.textContent=m;setTimeout(()=>f.textContent='',3000);}
"""


def e(v):
    return html.escape("" if v is None else str(v), quote=True)


def badge(status):
    return f'<span class="s {STATUS_CLASS.get(status, "muted")}">{e(status)}</span>'


def render(state):
    root = state["root"]
    dv = os.path.join(root, ".devflow")
    open_items = [i for i in state["items"] if i["state"] == "open"]
    done_items = [i for i in state["items"] if i["state"] != "open"]
    n_dec = sum(1 for i in open_items if i["kind"] == "decision")
    n_chk = sum(1 for i in open_items if i["kind"] == "check")
    running = [r for r in state["runs"].values() if r["running"]]
    cur = next((s for s in state["stages"] if s["status"] == "进行中"), None) or (state["stages"][-1] if state["stages"] else None)
    if cur:
        done = sum(1 for c in cur["contracts"] if c["status"] == "完成")
        head = f'{e(cur["id"])} {e(cur["title"])} {badge(cur["status"])} · 计划契约 {done}/{len(cur["contracts"])} 完成'
    else:
        head = '尚未登记方案 <span class="muted small">（.devflow/roadmap.json 不存在或为空）</span>'
    run_txt = "；".join(f'{e(r["id"])} {badge(r["status"])}' for r in running) or "无"
    out = ['<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width,initial-scale=1">',
           f'<title>方案进展</title><style>{CSS}</style></head><body><main>',
           f'<h1>方案进展</h1><div class="muted small">{e(root)} · 生成于 {e(fmt_local(state["generated_at"]))}'
           '<span id="paused" hidden> · 你正在作答，已暂停自动刷新</span></div>',
           f'<div class="top" style="margin-top:12px"><div class="line">{head}</div>',
           f'<div class="small" style="margin-top:6px">花费：{e(state["cost"]["label"])} · '
           f'等你处理：<b>{n_dec}</b> 决策 · <b>{n_chk}</b> 人工项 · 正在运行：{run_txt}</div></div>']
    for err in state["errors"]:
        out.append(f'<div class="err small">登记错误：{e(err)}</div>')

    out.append('<h2>等你处理</h2>')
    if not open_items:
        out.append('<p class="muted">没有待处理事项。</p>')
    for i in [x for x in open_items if x["kind"] == "decision"]:
        out.append(f'<div class="item" data-item="{e(i["id"])}" data-kind="decision" data-done="0">'
                   f'<span class="s warn">决策</span><div><span class="id">{e(i["id"])}</span> {e(i["text"])}</div>'
                   '<div class="ctl"><input type="text" placeholder="你的决定（填写后生成答复即记为已决定）"></div></div>')
    groups = {}
    for i in [x for x in open_items if x["kind"] == "check"]:
        groups.setdefault(i["id"].rsplit("/", 1)[0], []).append(i)
    for g, lst in groups.items():
        out.append(f'<details><summary><span class="s">人工项</span> {e(g)}（{len(lst)}）</summary><div class="body">')
        for i in lst:
            src = f' <span class="muted small">{e(i.get("source"))}</span>' if i.get("source") else ""
            out.append(f'<label class="chk" data-item="{e(i["id"])}" data-kind="check" data-done="0">'
                       f'<input type="checkbox"><div><span class="id">{e(i["id"])}</span> {e(i["text"])}{src}'
                       '<div class="note"><input type="text" placeholder="备注（可选）"></div></div></label>')
        out.append('</div></details>')
    if done_items:
        out.append(f'<details><summary>已处理的事项（{len(done_items)}）</summary><div class="body">')
        for i in done_items:
            a = i["answer"] or {}
            out.append(f'<div class="item" data-item="{e(i["id"])}" data-kind="{i["kind"]}" data-done="1">'
                       f'<span class="s ok">{e(a.get("action"))}</span><div><span class="id">{e(i["id"])}</span> '
                       f'{e(i["text"])}<div class="small muted">{e(a.get("text"))} · {e(a.get("ts"))}</div></div>'
                       '<div class="ctl"><label><input type="checkbox"> 撤回</label></div></div>')
        out.append('</div></details>')
    out.append('<p><button onclick="gen()">生成答复</button> <span id="flash" class="small muted"></span></p>'
               '<div id="replybox" hidden><p class="small muted">把下面的内容交给任意 Claude 会话执行，'
               '或者在 Claude Code 里用 <code>!</code> 直接运行命令。</p><textarea id="reply" readonly></textarea>'
               '<p><button onclick="copyReply()">复制</button></p></div>')

    out.append('<h2>阶段</h2>')
    if not state["stages"]:
        out.append('<p class="muted">登记表里还没有阶段。</p>')
    for st in state["stages"]:
        sync = f' <span class="s warn">{e(st["sync"])}</span>' if st["sync"] else ""
        out.append(f'<details{" open" if st is cur else ""}><summary><b>{e(st["id"])}</b> {e(st["title"])} '
                   f'{badge(st["status"])}{sync} <span class="muted small">{e(st["cost"]["label"])}</span></summary>'
                   f'<div class="body"><div class="small muted">计划：{e(st["plan"] or "未出计划")}</div>')
        for c in st["contracts"]:
            out.append(f'<details><summary>{e(c["title"])} {badge(c["status"])} '
                       f'<span class="muted small">{len(c["runs"])} 次运行 · {e(c["cost"]["label"])}</span></summary><div class="body">')
            for rid in c["runs"]:
                out.append(run_html(state["runs"][rid]))
            out.append('</div></details>')
        out.append('</div></details>')
    if state["unattached"]:
        out.append(f'<h2>未挂接的运行（{len(state["unattached"])}）</h2>'
                   '<p class="small muted">契约存在，但登记表里找不到。下次武装或续跑时登记，或手工补登。</p>')
        for rid in state["unattached"]:
            out.append(run_html(state["runs"][rid]))
    log_cmd = shlex.quote(os.path.join(SCRIPT_DIR, "log.sh"))
    refresh = "python3 -I " + shlex.quote(os.path.join(SCRIPT_DIR, "status.py")) + " " + shlex.quote(root)
    out.append(f'<script>const LOG={json.dumps(log_cmd)};const TSV={json.dumps(os.path.join(dv, "roadmap.tsv"))};'
               f'const REFRESH={json.dumps(refresh)};{JS}</script></main></body></html>')
    return "\n".join(out)


def run_html(r):
    cost = r["cost"]
    if cost["state"] == "ok":
        ctext = fmt_cost(cost["value"]) + (f" / {fmt_cost(cost['cap'])}" if cost.get("cap") else "")
    else:
        ctext = cost["state"] + (f"（{cost.get('reason')}）" if cost.get("reason") else "")
    rows = "".join(f'<tr><td class="nw" title="{e(ev["ts"])}">{e(fmt_local(parse_ts(ev["ts"])))}</td><td class="nw">{e(ev["phase"])}</td><td>{e(ev["decision"])}</td>'
                   f'<td>{e(ev["result"])}</td><td><code>{e(ev["evidence"])}</code></td></tr>' for ev in r["events"])
    return (f'<details><summary><code>{e(r["id"])}</code> {badge(r["status"])} '
            f'<span class="muted small">最后更新 {e(fmt_local(r["last_update"]))} · 花费 {e(ctext)}</span></summary>'
            f'<div class="body"><div class="small">完成条件：{e(r["condition"] or "—")}</div>'
            + (f'<table><tr><th>时间</th><th>阶段</th><th>决定</th><th>结果</th><th>证据</th></tr>{rows}</table>' if rows else "")
            + '</div></details>')


# ---------- register ----------

def parse_contract(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    if not lines or not lines[0].startswith(CONTRACT_TITLE):
        raise ValueError(f"{path} 不是自动运行契约（首行应以 {CONTRACT_TITLE} 开头）")
    out = {"stage": None, "contract": None, "plan": None, "cost_cmd": None, "cost_cap": None, "checks": []}
    in_checks = False
    for line in lines[1:]:
        if in_checks:
            m = re.match(r"^\s+- ([^：:\s]+)[：:]\s*(.+)$", line)
            if m:
                out["checks"].append((plain(m.group(1)), plain(m.group(2))))
                continue
            if line.startswith((" ", "\t")):
                continue
            in_checks = False
        if m := re.match(r"^- 阶段：\s*(\S+)\s*$", line):
            out["stage"] = m.group(1)
        elif m := re.match(r"^- 计划契约：\s*(\S+)\s*$", line):
            out["contract"] = m.group(1)
        elif m := re.match(r"^- 计划文件：\s*`?([^`\s]+)`?\s*$", line):
            out["plan"] = m.group(1)
        elif line.startswith("- 花费："):
            if m := re.search(r"命令\s*`([^`]+)`", line):
                out["cost_cmd"] = m.group(1)
            if m := re.search(r"上限\s*\$\s*([0-9.]+)", line):
                out["cost_cap"] = float(m.group(1))
        elif line.startswith("- 人工项"):
            in_checks = True
    if not out["stage"] or not out["contract"]:
        raise ValueError("契约缺少必填字段：`- 阶段：<编号>` 和 `- 计划契约：<编号>`")
    return out


def plain(text):
    """Drop Markdown emphasis markers so stored text reads cleanly on the page."""
    return re.sub(r"(\*\*|__)", "", text).strip("*` ").strip()


def parse_plan_checks(path):
    """Rows of the first Markdown table under a heading that contains 人工项: | 编号 | 内容 | ..."""
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    out, in_sec, in_table = [], False, False
    for line in lines:
        if line.startswith("#"):
            if in_table:
                break
            in_sec = "人工项" in line
            continue
        if not in_sec:
            continue
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not in_table:
                in_table = True
                continue
            if all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                continue
            if len(cells) >= 2 and cells[0]:
                out.append((plain(cells[0]), plain(cells[1])))
        elif in_table:
            break
    return out


def register(root, slug, apply, expect):
    dv = os.path.join(root, ".devflow")
    path = os.path.join(dv, "roadmap.json")
    cur_sha = sha256_file(path)
    current, err = load_json(path)
    if err:
        print(f"登记表无法解析：{err}", file=sys.stderr)
        return 2
    rm = json.loads(json.dumps(current)) if current else {"version": 1, "stages": [], "checks": [], "runs": {}}
    rm.setdefault("stages", []); rm.setdefault("checks", []); rm.setdefault("runs", {})
    try:
        c = parse_contract(os.path.join(dv, slug + ".md"))
    except (OSError, ValueError) as ex:
        print(f"无法登记：{ex}", file=sys.stderr)
        return 2
    stage = next((s for s in rm["stages"] if s.get("id") == c["stage"]), None)
    if stage is None:
        stage = {"id": c["stage"], "title": "", "plan": "", "plan_sha256": "", "contracts": []}
        rm["stages"].append(stage)
    for s in rm["stages"]:
        for pc in s.get("contracts") or []:
            if slug in (pc.get("runs") or []) and not (s is stage and pc.get("id") == c["contract"]):
                print(f"无法登记：运行 {slug} 已挂在 {s.get('id')}/{pc.get('id')} 下", file=sys.stderr)
                return 2
    pc = next((x for x in stage["contracts"] if x.get("id") == c["contract"]), None)
    if pc is None:
        pc = {"id": c["contract"], "title": c["contract"], "runs": []}
        stage["contracts"].append(pc)
    if slug not in pc["runs"]:
        pc["runs"].append(slug)
    new_checks = []
    if c["plan"]:
        stage["plan"] = c["plan"]
        ppath = os.path.join(root, c["plan"])
        stage["plan_sha256"] = sha256_file(ppath)
        if stage["plan_sha256"] == "none":
            print(f"无法登记：计划文件不存在：{c['plan']}", file=sys.stderr)
            return 2
        if not stage.get("title"):
            with open(ppath, encoding="utf-8") as f:
                h1 = next((l[2:].strip() for l in f if l.startswith("# ")), "")
            stage["title"] = h1
        new_checks += [(f"{c['stage']}/{i}", t, f"{c['plan']} 人工项") for i, t in parse_plan_checks(ppath)]
    new_checks += [(f"{slug}/{i}", t, f".devflow/{slug}.md 人工项") for i, t in c["checks"]]
    conflicts = []
    for cid, text, src in new_checks:
        old = next((x for x in rm["checks"] if x.get("id") == cid), None)
        if old is None:
            rm["checks"].append({"id": cid, "text": text, "source": src})
        elif old.get("text") != text:
            conflicts.append(f"人工项 {cid} 已登记为「{old.get('text')}」，契约或计划中为「{text}」")
    if conflicts:
        print("登记错误，未写入：\n" + "\n".join(conflicts), file=sys.stderr)
        return 2
    meta = {k: c[k] for k in ("cost_cmd", "cost_cap") if c[k] is not None}
    if meta:
        rm["runs"][slug] = meta
    else:
        rm["runs"].pop(slug, None)
    before = json.dumps(current, ensure_ascii=False, indent=2).splitlines() if current else []
    after = json.dumps(rm, ensure_ascii=False, indent=2).splitlines()
    if not apply:
        print(f"当前登记表 sha256：{cur_sha}")
        diff = list(difflib.unified_diff(before, after, "roadmap.json（当前）", "roadmap.json（登记后）", lineterm=""))
        print("\n".join(diff) if diff else "（没有改动）")
        return 0
    if expect != cur_sha:
        print(f"登记表已被改动（当前 {cur_sha}，预期 {expect}），请重新 --dry-run 后再确认", file=sys.stderr)
        return 3
    write_atomic(path, json.dumps(rm, ensure_ascii=False, indent=2) + "\n")
    print(f"已登记 {slug} → {c['stage']}/{c['contract']}；登记表 sha256：{sha256_file(path)}")
    return 0


# ---------- main ----------

def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    root = os.path.realpath(argv[1])
    dv = os.path.join(root, ".devflow")
    if not os.path.isdir(dv):
        print(f"没有 {dv}", file=sys.stderr)
        return 2
    args = argv[2:]
    with open(os.path.join(dv, "status.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args[:1] == ["register"]:
            if len(args) < 2:
                print("用法：status.py <root> register <slug> --dry-run | --apply --expect <sha256>", file=sys.stderr)
                return 2
            apply = "--apply" in args
            expect = args[args.index("--expect") + 1] if "--expect" in args and args.index("--expect") + 1 < len(args) else None
            if apply and not expect:
                print("--apply 需要 --expect <sha256>（取自 --dry-run 的输出）", file=sys.stderr)
                return 2
            return register(root, args[1], apply, expect)
        prev, _ = load_json(os.path.join(dv, "status.json"))
        state = build(root, prev if isinstance(prev, dict) else None)
        write_atomic(os.path.join(dv, "status.json"), json.dumps(state, ensure_ascii=False, indent=1))
        write_atomic(os.path.join(dv, "status.html"), render(state))
        if "--notify" in args:
            print(json.dumps(notify(dv, state), ensure_ascii=False))
        elif "--summary" in args:
            print(summary(state))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
