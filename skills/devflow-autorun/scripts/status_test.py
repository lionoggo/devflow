"""Cases for status.py; run through status-test.sh."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone

STATUS, LOG = sys.argv[1], sys.argv[2]
HEAD = "ts\tphase\tdecision\twhy\tevidence\tresult\n"
passed = failed = 0


def check(cond, name, detail=""):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {name} {detail}")


def ts(minutes_ago=0):
    return (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).strftime("%Y-%m-%dT%H:%M:%SZ")


class Repo:
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="status-test-")
        self.dv = os.path.join(self.root, ".devflow")
        os.makedirs(self.dv)

    def contract(self, slug, extra=""):
        self.write(f".devflow/{slug}.md", f"# 自动运行契约：{slug}\n\n- 目标：x\n{extra}")

    def log(self, slug, *rows):
        path = os.path.join(self.dv, slug + ".tsv")
        new = not os.path.exists(path)
        with open(path, "a") as f:
            if new:
                f.write(HEAD)
            for r in rows:
                f.write("\t".join(r) + "\n")

    def write(self, rel, text):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)

    def roadmap(self, stages, checks=(), runs=None):
        self.write(".devflow/roadmap.json", json.dumps({"version": 1, "stages": stages, "checks": list(checks),
                                                       "runs": runs or {}}, ensure_ascii=False))

    def run(self, *args, env=None):
        e = dict(os.environ, **(env or {}))
        return subprocess.run([sys.executable, "-I", STATUS, self.root, *args], capture_output=True, text=True, env=e)

    def state(self):
        with open(os.path.join(self.dv, "status.json")) as f:
            return json.load(f)

    def notify(self, env=None):
        p = self.run("--notify", env=env)
        return json.loads(p.stdout)["events"] if p.returncode == 0 else ["ERROR", p.stderr]

    def done(self):
        shutil.rmtree(self.root)


def stage(sid, plan, contracts, sha=""):
    return {"id": sid, "title": sid, "plan": plan, "plan_sha256": sha,
            "contracts": [{"id": c, "title": c, "runs": r} for c, r in contracts]}


# --- run states, stale, unattached, parse error, drafts ---
r = Repo()
r.write("plan.md", "# P\n")
for s in ("a", "b", "c", "d", "e", "loose"):
    r.contract(s)
r.log("a", (ts(2), "start", "armed", "", "", ""))
r.write(".devflow/a.running", "{}")
r.log("b", (ts(120), "start", "armed", "", "", ""))
r.write(".devflow/b.running", "{}")
r.log("c", (ts(5), "start", "armed", "", "", ""), (ts(1), "close", "说不清", "", "", ""))
r.log("d", (ts(5), "start", "armed", "", "", ""))
r.log("loose", (ts(5), "close", "完成", "", "", ""))
r.write(".devflow/notes.md", "# 不是契约\n")
r.roadmap([stage("S1", "plan.md", [("ca", ["a"]), ("cb", ["b"]), ("cc", ["c"]), ("cd", ["d"]), ("ce", ["e"])]),
           stage("S2", "plan.md", []), stage("S3", "", [("x", ["e"])])])
p = r.run()
st = r.state()
runs = {k: v["status"] for k, v in st["runs"].items()}
check(p.returncode == 0, "plain run exits 0", p.stderr)
check(runs.get("a") == "运行中", "recent running", runs)
check(runs.get("b") == "运行中·可能失联", "stale running", runs)
check(runs.get("c") == "解析错误", "unparseable close decision", runs)
check(runs.get("d") == "未收尾", "log without close or marker", runs)
check(runs.get("e") == "起草中", "contract only", runs)
check("notes" not in runs, "non-contract md ignored", runs)
check(st["unattached"] == ["loose"], "unattached run", st["unattached"])
s1 = st["stages"][0]
ce = next(c for c in s1["contracts"] if c["id"] == "ce")
check(ce["status"] == "未开始", "contract with only a draft run is not started", ce)
check(st["stages"][1]["status"] == "未开始", "stage without contracts is not started")
check(st["stages"][2]["status"] == "未开始", "stage without plan is not started")
check(any("重复登记" in e for e in st["errors"]), "run registered twice is an error", st["errors"])
r.roadmap([stage("S1", "plan.md", [("ca", ["a", "ghost"])])])
r.run()
check(any("ghost" in e for e in r.state()["errors"]), "missing registered run is an error")
r.done()

# --- plan sync, stage done, retry order, parked in either column, answers ---
r = Repo()
r.write("plan.md", "# P\n")
import hashlib
sha = hashlib.sha256(open(os.path.join(r.root, "plan.md"), "rb").read()).hexdigest()
for s in ("x1", "x2", "y"):
    r.contract(s)
r.log("x1", (ts(9), "start", "armed", "", "", ""), (ts(8), "U1", "tried", "", "", "parked: need user"),
      (ts(7), "close", "受阻 — parked", "", "", "P1 not met"))
r.log("x2", (ts(6), "start", "armed", "", "", ""), (ts(5), "close", "完成", "", "", "all pass"))
r.log("y", (ts(6), "start", "armed", "", "", ""), (ts(5), "B8", "parked: fixture", "", "", "cannot pass"),
      (ts(4), "close", "部分完成 — y", "", "", "x"))
r.roadmap([stage("S1", "plan.md", [("x", ["x1", "x2"]), ("y", ["y"])], sha)], checks=[{"id": "S1/H1", "text": "look"}])
r.run()
st = r.state()
x = next(c for c in st["stages"][0]["contracts"] if c["id"] == "x")
check(x["status"] == "完成", "last run in runs order decides", x)
check(st["stages"][0]["sync"] is None, "plan in sync")
decs = sorted(i["id"] for i in st["items"] if i["kind"] == "decision")
check(decs == ["x1/D1", "y/D1"], "parked in result or decision column", decs)
r.write("plan.md", "# P changed\n")
r.run()
check(r.state()["stages"][0]["sync"] == "登记待同步", "plan changed -> needs sync")
with open(os.path.join(r.dv, "roadmap.tsv"), "w") as f:
    f.write(HEAD + HEAD)
subprocess.run([LOG, os.path.join(r.dv, "roadmap.tsv"), "user", "S1/H1 已处理", "done it", "", ""], check=True)
with open(os.path.join(r.dv, "roadmap.tsv"), "a") as f:
    f.write(HEAD)
subprocess.run([LOG, os.path.join(r.dv, "roadmap.tsv"), "user", "y/D1 已决定", "<b>fix</b> it's", "", ""], check=True)
r.run()
st = r.state()
state = {i["id"]: i["state"] for i in st["items"]}
check(state == {"x1/D1": "open", "y/D1": "done", "S1/H1": "done"}, "answers applied despite repeated headers", state)
html = open(os.path.join(r.dv, "status.html")).read()
check("<b>fix</b>" not in html and "&lt;b&gt;fix&lt;/b&gt;" in html, "page escapes source text")
subprocess.run([LOG, os.path.join(r.dv, "roadmap.tsv"), "user", "S1/H1 撤回", "", "", ""], check=True)
r.run()
check({i["id"]: i["state"] for i in r.state()["items"]}["S1/H1"] == "open", "withdraw reopens")
r.done()

# --- cost ---
r = Repo()
for s in ("k1", "k2", "k3", "k4", "k5"):
    r.contract(s)
    r.log(s, (ts(3), "start", "armed", "", "", ""), (ts(2), "close", "完成", "", "", ""))
counter = os.path.join(r.root, "count")
r.roadmap([stage("S", "", [("k", ["k1", "k2"]), ("m", ["k3", "k4", "k5"])])],
          runs={"k1": {"cost_cmd": f"echo x >> {counter}; echo 12.5", "cost_cap": 30},
                "k2": {"cost_cmd": "echo 2"},
                "k3": {"cost_cmd": "echo abc"}, "k4": {"cost_cmd": "exit 3"}, "k5": {"cost_cmd": "sleep 5; echo 1"}})
r.run(env={"DEVFLOW_COST_TIMEOUT": "1"})
st = r.state()
c = {k: v["cost"] for k, v in st["runs"].items()}
check(c["k1"]["state"] == "ok" and c["k1"]["value"] == 12.5, "cost value", c["k1"])
check(all(c[k]["state"] == "读取失败" for k in ("k3", "k4", "k5")), "bad, failing and slow cost -> 读取失败",
      {k: c[k]["state"] for k in ("k3", "k4", "k5")})
k = next(x for x in st["stages"][0]["contracts"] if x["id"] == "k")
check(k["cost"]["label"] == "$14.50", "contract cost sums its runs", k["cost"])
check(st["cost"]["label"].startswith("至少 $14.50"), "unknown cost marks the total partial", st["cost"])
r.run(env={"DEVFLOW_COST_TIMEOUT": "1"})
check(open(counter).read().count("x") == 1, "closed run reuses the cached cost")
r.done()

# --- notify: baseline, corrupt, quiet, manual refresh first, concurrency, slow refresh ordering ---
r = Repo()
r.contract("n")
r.log("n", (ts(3), "start", "armed", "", "", ""))
r.write(".devflow/n.running", "{}")
r.roadmap([stage("S", "", [("n", ["n"])])])
check(r.notify() == [], "first --notify is a baseline")
r.write(".devflow/notify-state.json", "{broken")
check(r.notify() == [], "corrupt notify state -> baseline")
check(r.notify() == [] and r.notify() == [] and r.notify() == [], "no business change -> no events")
r.log("n", (ts(1), "U1", "x", "", "", "parked: pick one"))
r.run()
ev = r.notify()
check([e["type"] for e in ev] == ["new_decision"], "plain refresh does not consume events", ev)
r.log("n", (ts(0), "U2", "y", "", "", "parked: pick two"))
procs = [subprocess.Popen([sys.executable, "-I", STATUS, r.root, "--notify"], stdout=subprocess.PIPE, text=True,
                          env=dict(os.environ, DEVFLOW_TEST_NOTIFY_PAUSE="1")) for _ in range(2)]
outs = [json.loads(p.communicate()[0])["events"] for p in procs]
check(sorted(len(o) for o in outs) == [0, 1], "concurrent --notify hands an event to one caller", outs)
# slow only while the run is live: the refresh started first is slow, the --notify started later is fast,
# so without the lock the older refresh would write last and put "运行中" back on the page
r.roadmap([stage("S", "", [("n", ["n"])])], runs={"n": {"cost_cmd": "[ -f .devflow/n.running ] && sleep 3; echo 1"}})
slow = subprocess.Popen([sys.executable, "-I", STATUS, r.root], env=dict(os.environ, DEVFLOW_COST_TIMEOUT="10"))
time.sleep(1)
r.log("n", (ts(0), "close", "完成", "", "", "ok"))
os.remove(os.path.join(r.dv, "n.running"))
ev = r.notify(env={"DEVFLOW_COST_TIMEOUT": "10"})
slow.wait()
check(r.state()["runs"]["n"]["status"] == "完成", "slow older refresh does not overwrite the newer page")
check([e["type"] for e in ev] == ["run_end"], "--notify waits for the lock and sees the close", ev)
check(r.notify() == [], "no duplicate run_end afterwards")
r.done()

# --- register ---
r = Repo()
r.write("docs/plan.md", "# 计划甲\n\n## 6. 人工项\n\n| ID | 内容 | 方法 |\n|---|---|---|\n| **H1** | **基线** B0 | x |\n| H2 | 通读 | y |\n\n## 7. 其他\n")
r.contract("r1", "- 阶段：P1\n- 计划契约：core\n- 计划文件：`docs/plan.md`\n- 花费：命令 `echo 3`；上限 $30\n"
                 "- 人工项（不计入完成）：\n  - B7：抽查产物\n- 写入范围：src/\n")
r.contract("r2", "- 阶段：P1\n- 计划契约：core\n- 人工项：\n  - B7：抽查产物\n")
r.contract("bad", "- 计划契约：core\n")
r.contract("r3", "- 阶段：P1\n- 计划契约：core\n- 计划文件：docs/plan.md\n")
p = r.run("register", "bad", "--dry-run")
check(p.returncode == 2 and "必填" in p.stderr, "missing stage field is refused", p.stderr)
p = r.run("register", "r1", "--dry-run")
check(p.returncode == 0 and "sha256：none" in p.stdout, "dry-run on a new roadmap", p.stdout[:200])
check(not os.path.exists(os.path.join(r.dv, "roadmap.json")), "dry-run writes nothing")
p = r.run("register", "r1", "--apply", "--expect", "deadbeef")
check(p.returncode == 3, "stale --expect is refused", p.stderr)
p = r.run("register", "r1", "--apply", "--expect", "none")
check(p.returncode == 0, "apply", p.stderr)
rm = json.load(open(os.path.join(r.dv, "roadmap.json")))
ids = [c["id"] for c in rm["checks"]]
check(ids == ["P1/H1", "P1/H2", "r1/B7"], "plan and contract checks registered", ids)
check(rm["checks"][0]["text"] == "基线 B0", "markdown emphasis stripped", rm["checks"][0])
check(rm["runs"]["r1"] == {"cost_cmd": "echo 3", "cost_cap": 30.0}, "cost registered", rm["runs"])
check(rm["stages"][0]["title"] == "计划甲" and rm["stages"][0]["plan"] == "docs/plan.md", "stage from plan", rm["stages"][0])


def apply(slug):
    d = r.run("register", slug, "--dry-run")
    sha = d.stdout.split("sha256：", 1)[1].split()[0] if "sha256：" in d.stdout else "?"
    return r.run("register", slug, "--apply", "--expect", sha)


check(apply("r1").returncode == 0, "re-register is idempotent")
check(apply("r2").returncode == 0, "retry run appended")
rm = json.load(open(os.path.join(r.dv, "roadmap.json")))
check(rm["stages"][0]["contracts"][0]["runs"] == ["r1", "r2"], "runs keep order without duplicates",
      rm["stages"][0]["contracts"])
r.write("docs/plan.md", "# 计划甲\n\n## 6. 人工项\n\n| ID | 内容 |\n|---|---|\n| H1 | 改过的内容 |\n")
p = apply("r3")
check(p.returncode == 2 and "P1/H1" in p.stderr, "conflicting check text is refused", p.stderr)
r.run()
check(r.state()["runs"]["r1"]["cost"]["value"] == 3.0, "registered cost command is used")
r.done()

print(f"status-test: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
