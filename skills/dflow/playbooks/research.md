### 调研 (research)

**Explain how existing code or a project works, or why it is built that way,
with every key claim tied to evidence. Read-only.** From devflow-research and
pstack `how`, `why`. Principles: 以现状为准, 解释数字, 真实证据.

1. Name the target and the question. Split it: **how** (what the code does,
   where things live, the runtime flow) or **why** (what forces shaped it).
   Vague target: state your best reading and go on.
2. **How.** Judge the size first.
   - **Simple** (one module, one function, a narrow question): read the main
     path yourself.
   - **Complex** (a subsystem across many files or services, a cross-cutting
     feature, a whole-project overview): split the question into 2–4 angles
     that do not overlap (for example entry and flow, data and storage,
     configuration and boundaries). In one message, start one read-only Claude
     subagent per angle (the Explore agent type, model Opus or lower) and
     give one more angle to `codex exec -s read-only` in the background, all
     with `references/research-explorer-prompt.md`. Then you synthesize:
     merge overlaps, settle every contradiction by reading the code yourself,
     and read the main path yourself before stating it. Explorer findings are
     leads, not evidence. Name which angle each explorer took, and write
     "codex 未参与：<原因>" when it could not run.
   When in doubt, take the simple path.
   For either size: read the main path yourself, entry to effect. Tie each key claim
   to `path:line` taken from numbered output; otherwise cite file and symbol.
   Keep each claim's conditions (only when configured, fallback, default vs
   opt-in). When behavior depends on prompts, config, or environment, confirm
   it in a real run artifact.
3. **Why:** build the anchor first: `git blame -L`, `git log --follow -p`,
   commit bodies, PR descriptions (`gh pr view`, read-only) and linked docs.
   Then check every other source this session can read (issue tracker,
   chat, long-form docs, error tracking, observability, through whatever
   tools or MCP servers are connected), one read-only subagent per source
   when there are several; record "无此来源" for each category with no tool.
   Code cannot prove its own intent; grade each rationale with
   `references/epistemics.md` and write 推测 where nothing written says it.
   A search that finds nothing is an answer; say what you searched.
4. Examples are labeled 实际演练 (run in this session) or 推演 (derived from
   code). Never present predicted output as observed. Do not install
   dependencies or create environments to run something.
5. For each key design, say the problem it solves and its cost. Answer the
   question asked; mention adjacent findings in one line. A question that
   turns into "why is it broken" goes to 排查; "what should we change" goes to
   方案.
6. Output, lightest that answers it:
   - Default: a few paragraphs in the reply with the decisive locations.
   - A document when the user asks or the chain is too long:
     `docs/research/<topic>.md`, shaped by `references/research-report-template.md`,
     with the commit hash; run it through `references/unslop.md` and commit it
     locally. Diagrams per `references/research-diagrams.md` when a
     relationship is hard to follow in prose.
   - Industry comparison (`references/research-industry-comparison.md`; for
     outside sources `references/prior-art-research.md`) or an HTML demo
     (`references/research-html-demo.md`) only on request; otherwise offer it
     in one line.

**Reply:**

```text
**结论**：<一两句话回答问题>
- 怎么工作：<主路径，关键位置 path:line>
- 为什么这样：<依据和置信；没有书面依据的写推测和怎么核实>
- 例子：<实际演练 / 推演>
- 文档：<路径；没写就省略>
- 未核实：<最重要的一条；没有就省略>
```
