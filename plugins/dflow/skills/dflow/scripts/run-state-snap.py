"""The no-commit baseline of a dflow unattended run, written and compared for run-state.sh.

Usage: run-state-snap.py make|check|scope|state|changed <repo root> <manifest> <baseline json>

What it sees: paths that differ from HEAD (tracked changes, staged or not, and untracked files Git
does not ignore), the index, and ignored files under the literal directory of each allow and
protect glob ("watched" files). A path's entry is its type, permission bits and content
(f<octal mode>:<sha256>, link:<target hex>, missing). It refuses what it cannot judge instead of
passing it: a directory in place of a file (nested repository), a submodule inside or around any
allow or protect glob, index entries marked assume-unchanged or skip-worktree, an empty allow,
and an allow or protect glob with a wildcard before any directory part (`*.png`), since ignored
files under it cannot be listed.

make     write the baseline (refused when it exists; published with a hard link, never replaced)
check    compare with the baseline; watched files keep their baseline entry while size and mtime
         are unchanged (a fast path), every other path is hashed
scope    the same comparison, hashing every watched file
state    one id for what a check or review covered: base, baseline, index and every changed entry
changed  one JSON line [path, entry] per path that differs from the baseline, for review material
Exit 1 with one line per finding; 2 when something cannot be judged.
"""
import fnmatch, hashlib, json, os, re, stat, subprocess, sys

mode, root, man, bl = sys.argv[1:5]


def fail(msg, code=2):
    print("FAIL " + msg)
    sys.exit(code)


def field(k):  # same rule as field() in run-state.sh: the leading key: value block
    seen = False
    for line in open(man, encoding="utf-8"):
        if not line.strip():
            if seen: break
        elif re.match(r"[a-z0-9_]+: ", line):
            seen = True
            if line.startswith(k + ": "): return line[len(k) + 2:].rstrip("\n")
    return ""


allow, protect = field("allow").split(), field("protect").split()
if not allow: fail("a no-commit run needs allow: globs in the manifest")


def literal_dir(g):  # the part to list ignored files under: a plain path, or the directory before the first wildcard
    w = [i for i, ch in enumerate(g) if ch in "*?["]
    if not w: return g
    d = g[:w[0]][:g[:w[0]].rfind("/") + 1]
    if not d: fail(f"glob {g} has a wildcard before any directory part; ignored files under it cannot be listed (name a directory, e.g. assets/{g})")
    return d


watch_dirs = sorted({literal_dir(g) for g in allow + protect})


def git(*a): return subprocess.run(["git", "-C", root, *a], check=True, capture_output=True).stdout
def paths(b): return [p for p in b.decode("utf-8", "surrogateescape").split("\0") if p and not (p == ".dflow" or p.startswith(".dflow/"))]
def match(p, globs): return any(fnmatch.fnmatchcase(p, g) for g in globs)


def entry(p):
    f = os.path.join(root, p)
    try: s = os.lstat(f)
    except FileNotFoundError: return "missing"
    if stat.S_ISLNK(s.st_mode): return "link:" + os.fsencode(os.readlink(f)).hex()
    if not stat.S_ISREG(s.st_mode): fail(f"{p} is not a file (a submodule or nested repository?); a no-commit run does not support it")
    h = hashlib.sha256()
    with open(f, "rb") as fh:
        for c in iter(lambda: fh.read(1 << 20), b""): h.update(c)
    return f"f{stat.S_IMODE(s.st_mode):o}:" + h.hexdigest()


def statkey(p):
    try: s = os.lstat(os.path.join(root, p)); return [s.st_size, s.st_mtime_ns, s.st_mode]
    except FileNotFoundError: return None


def dirty():
    return set(paths(git("diff", "--name-only", "-z", "HEAD"))) | set(paths(git("ls-files", "-z", "-o", "--exclude-standard")))


def watched():
    return sorted(p for p in paths(git("ls-files", "-z", "-o", "-i", "--exclude-standard", "--", *[":(literal)" + d for d in watch_dirs]))
                  if match(p, allow + protect))


def index():
    for line in git("ls-files", "-s", "-z").decode("utf-8", "surrogateescape").split("\0"):
        if line.startswith("160000 "):
            p = line.split("\t", 1)[1]
            if any(match(p, [g]) or match(p + "/", [g]) or g.startswith(p + "/") or p.startswith(literal_dir(g)) for g in allow + protect):
                fail(f"submodule {p} is inside or around an allow or protect glob; a no-commit run does not support it")
    flagged = [line[2:] for line in git("ls-files", "-v", "-z").decode("utf-8", "surrogateescape").split("\0")
               if line and (line[0].islower() or line[0] == "S")]
    if flagged: fail(f"index entries marked assume-unchanged or skip-worktree hide changes ({flagged[0]}); a no-commit run does not support them")
    return hashlib.sha256(git("ls-files", "-s", "-z")).hexdigest()


def head(): return git("rev-parse", "HEAD").decode().strip()


if mode == "make":
    data = {"head": head(), "index": index(), "dirty": {p: entry(p) for p in sorted(dirty())},
            "watched": {p: [statkey(p), entry(p)] for p in watched()}}
    tmp = f"{bl}.tmp.{os.getpid()}"
    with open(tmp, "w") as f: json.dump(data, f, indent=0, sort_keys=True)
    try: os.link(tmp, bl)  # fails when another baseline got there first
    except FileExistsError: fail(f"baseline {bl} exists; it is written once, at 开始", 1)
    finally: os.unlink(tmp)
    sys.exit(0)

b = json.load(open(bl))
idx = index()  # refuses submodules and hidden index entries before anything is compared
tracked = set(paths(git("ls-files", "-z")))
now, cur = dirty(), set(watched())


def now_entry(p):  # a tracked path Git does not report equals HEAD; anything else is read from disk
    return "HEAD" if p in tracked and p not in now else entry(p)


def base_entry(p):
    if p in b["dirty"]: return b["dirty"][p]
    if p in b["watched"]: return b["watched"][p][1]
    return "HEAD" if p in tracked else "missing"


changed = {}
for p in sorted(now | cur | set(b["dirty"]) | set(b["watched"])):
    old = b["watched"].get(p)
    if mode == "check" and old and p in cur and p not in now and statkey(p) == old[0]: continue  # fast path
    e = now_entry(p)
    if e != base_entry(p): changed[p] = e

if mode == "changed":
    for p, e in changed.items(): print(json.dumps([p, e]))
    sys.exit(0)
if mode == "state":
    blsha = hashlib.sha256(open(bl, "rb").read()).hexdigest()
    ident = json.dumps({"head": head(), "baseline": blsha, "index": idx, "changed": sorted(changed.items())}, sort_keys=True)
    print("state " + hashlib.sha256(ident.encode()).hexdigest())
    sys.exit(0)

bad = []
if head() != b["head"]: bad.append(f"HEAD moved from {b['head']}")
if idx != b["index"]: bad.append("INDEX changed (a no-commit run never stages)")
for p in changed:
    if match(p, protect): bad.append("PROTECTED " + p)
    elif not match(p, allow): bad.append("OUTSIDE " + p)
for line in bad: print(line)
if bad: sys.exit(1)
print(f"ok tree matches baseline: {len(changed)} changed, inside allow")
