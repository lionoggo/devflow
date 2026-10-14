# pstack 场景组 1：理解代码 + 设计 —— 对照分析

> 范围：pstack（`plugins/pstack`，下称 P）中 how / why / teach / recall / in-your-own-words / architect / arena / swarm / interrogate / blast-radius，poteto-mode 的 investigation / prototype / multi-phase-plan / eval 四个 playbook，`skills/poteto-mode/scripts/check-plan.mjs`，`docs/guide/03-understand.md`、`04-design.md`；对照 devflow（`/Users/lionoggo/Workspaces/devflow/skills`，下称 D）的 devflow-research、devflow-plan 及其 references。
> 路径约定：P 的路径相对 `plugins/pstack/`，D 的路径相对 `devflow/skills/`。
> 说明：任务里写的 `scripts/check-plan.mjs` 实际位于 `skills/poteto-mode/scripts/check-plan.mjs`（另有 `check-plan.test.ts`）。

## 0. 先说几个贯穿全组的事实

1. **P 的所有技能都是 `disable-model-invocation: true`**（例如 `skills/how/SKILL.md:4`、`skills/architect/SKILL.md:4`），只能由用户敲 `/how`，或由 `/poteto-mode` 这个总路由按规则调用（`skills/poteto-mode/SKILL.md:19-36`）。D 的技能则靠 description 自动触发。两种模式差别很大：P 依赖“一个总入口 + 显式斜杠命令”，D 依赖“技能描述匹配”。
2. **P 的“多模型”全靠 Cursor Task 工具的 `model` 参数**，按 `~/.cursor/rules/pstack-models.mdc` 每个角色一行配置（`skills/setup-pstack/SKILL.md:8,41-66`），默认组合是 `claude-opus-5-5-xhigh`（判断、写作）+ `grok-4.7-xhigh-fast`（探索、写代码）。Claude Code 的 Agent 工具只能选 `sonnet/opus/haiku/fable`，都是 Claude 家族。**跨家族只能靠 `codex exec`**（本机已安装 `/opt/homebrew/bin/codex`）。凡是 P 里“模型多样性是信号来源”的技能（arena、interrogate、architect），在 Claude Code 上要么降级成“同家族不同档位/不同提示”，要么接 codex。
3. **P 的子 agent 通用参数**：`subagent_type: generalPurpose`、`readonly: true/false`、`run_in_background: true`、`environment: "cloud"`（`skills/poteto-mode/SKILL.md:93-99`、`skills/swarm/SKILL.md:30`）。Claude Code 对应：`readonly` → `Explore` 或用户已有的 `~/.claude/agents/explorer.md`（工具限 Read/Grep/Glob/Bash）；`generalPurpose` → `general-purpose`；`run_in_background` 原生支持；`cloud` 只有 Agent 工具的 `isolation: "remote"`（可用性受限）或 `/schedule` 云端 routine，**没有可靠等价物**。
4. **用户自己的全局规则会和 P 的若干默认冲突**：AGENTS.md 要求“目标由用户设定……由用户决定”“不创建 worktree”“仅当能实质降低总成本才用 sub-agent”。P 的 architect 默认不设人工检查点（`skills/architect/SKILL.md:43`）、arena 默认给每个候选开 worktree（`skills/arena/SKILL.md:18`）、why 默认“全量并行”（`skills/why/SKILL.md:31`），都需要改写后才能用。

---

## 1. 快速弄懂一段代码 / 一个子系统 —— `/how`

**1) 问题**：我要改一块不熟的代码，想先在几分钟内得到“资深工程师带我入门”级别的心智模型。

**2) pstack 解法**
- 触发：`/how <问题>`；poteto-mode 在“非平凡改动、架构决策、are we sure?”时自动路由（`skills/poteto-mode/SKILL.md:19`）；Investigation playbook 第一步也走它（`skills/poteto-mode/playbooks/investigation.md:7`）。
- 步骤：先判复杂度（`skills/how/SKILL.md:13-20`）。简单问题：只派 1 个 explainer 自己探索并解释（`:17`）。复杂问题：拆 2–4 个角度，**同一条消息**并行派 explorer（`:24`），全部返回后再派 1 个 explainer 综合（`:28`），主线程只做轻度编辑，“不要大改”（`:32`）。拿不准时走简单路径（`:20`）。
- 关键规则：
  - explorer 输出固定 schema：Components Found / Flow / Files Read / Boundaries / Non-Obvious Things / Open Questions（`skills/how/references/explorer-prompt.md:19-35`），要求诚实写 gap（`:35`）。
  - explainer 负责调和 explorer 之间的矛盾，“自己查代码解决”（`explainer-prompt.md:19`），只在必要时补读（`:23`）。
  - 输出结构 Overview / Key Concepts / How It Works / Where Things Live / Gotchas（`explainer-prompt.md:29-46`）；用具体名字（“`UserService` 调 `AuthClient.refresh()`”，`:51`）；图只在澄清时画（`:40`）。
  - 模型分工：explorer 用快模型（grok），explainer 用 opus（`skills/how/SKILL.md:11`）。

**3) 机制类型**：子 agent 并行 + 多模型（快模型探索、强模型综合）。依赖 Cursor：Task 的 `readonly`、`pstack-models.mdc`。

**4) Claude Code 映射**：完全可实现。Skill `how`；explorer 用 `subagent_type: "Explore"` 或 `explorer`，`model: "haiku"/"sonnet"`；explainer 用 `general-purpose` + `model: "opus"`。“同一条消息并行派发”是 Agent 工具原生能力。唯一损失是“grok 做探索”的跨家族成分，这里本来就不是信号来源，不影响。

**5) 成本**：简单 1 个子 agent；复杂 3–5 个（2–4 explorer + 1 explainer）。

**6) devflow 对应物与差距**：`devflow-research/SKILL.md`。
- D 更强的地方：引用纪律更严，行号只能来自带行号的输出（`devflow-research/SKILL.md:13-16`），`[推测]` 标注（`:15`），条件保留（`:20-21`），实际演练/推演区分（`:22-23`），输出分级（直接回答 / 笔记 / 文档，`:35-49`），图表规则（`references/diagrams.md`）。
- D 缺的：没有“简单/复杂”分档和并行探索规程；子 agent 只被当作“线索”（`:17-18`），没有 explorer 的统一返回 schema；没有固定的“Where Things Live / Gotchas”这类面向“马上要改代码的人”的结构。
- D 多余的：industry-comparison、HTML demo 这些更像“写调研报告”，P 的 how 定位是“改代码前的入门”，更轻。

**7) 判断：改写后采用。** 保留 D 的引用和推测纪律，加入 P 的“简单/复杂分档 + explorer schema + 单 explainer 综合”，模型档位用 haiku/sonnet 探索、opus 综合。

---

## 2. 解释为什么这样设计 —— `/why`

**1) 问题**：这段代码为什么长这样、这个阈值为什么是 5、当初为什么选 Y？我想要带出处的答案，而不是模型的合理化猜测。

**2) pstack 解法**
- 触发：`/why ...`；Investigation playbook 遇到“动机类”问题时追加（`playbooks/investigation.md:7`）；architect 在设计改变所有权或分层时调用（`skills/architect/SKILL.md:23`）；blast-radius 借它的 step 2 拉 PR（`skills/blast-radius/SKILL.md:33`）。
- 步骤：
  1. 确定目标和问题，模糊时按上下文猜并说明（`skills/why/SKILL.md:19-23`）。
  2. **主线程内联建立“代码锚点”**：`git blame -L`、`git log --follow -p`、`git log --oneline -20`、从提交标题提 PR 号、`gh pr view --json ...comments,reviews`（`:25-27`）。锚点发给所有 investigator 和 synthesizer。
  3. 发现可用 MCP，映射到 7 类证据：源码史、工单、长文档、聊天、基础设施观测、错误追踪、分析仓库（`:33-47`）；**每类一个 investigator，同一条消息并行**，每个只管一个 MCP（`:49`）。代码看起来是防御式时追加 incident 查询（`:53`）。
  4. 跳过某类必须写明理由，只有“无 MCP”或“可证明无关”两种合法理由（`:68-75`）。
  5. 派 1 个 synthesizer（opus）按 epistemics 综合（`:77-84`），主线程呈现时**不得改写置信措辞**（`:88`）。若是改代码的前奏，最后转成 Preserve / Change / Avoid / Risk 约束（`:94`）。
- 关键规则（这是本技能的价值所在）：
  - 五级置信：Direct / Supported / Inferred / Speculative / Unknown，每级对应措辞（`references/epistemics.md:5-37`）。
  - **“代码不能作为它自身意图的证据”**（`epistemics.md:71`、`synthesizer-prompt.md:34`、`investigator-prompt.md:47-48` “Mechanics are not motivation”）。
  - 用户问题里自带的假设只当候选，不能附和（`epistemics.md:57-59` Sycophancy Trap）。
  - 空结果也是发现，要写出搜了什么（`investigator-prompt.md:40`、`epistemics.md:37`）。
  - investigator 只收集不下结论、不跨源追线索，跨源线索写进 Additional Leads（`investigator-prompt.md:38,51,83-84`）。
  - synthesizer 抽查引用（`synthesizer-prompt.md:44`），出厂前 7 项自检（`:117-127`）。
  - 输出：The Question / Code / What We Found / Infer / Competing Hypotheses / Don't Know / Sources Consulted / Confidence Summary（`SKILL.md:92`）。
  - 源码考古命令清单（`references/sources/code-archaeology.md:18-51`：`git log -S` pickaxe、`-G`、ADR、TODO/FIXME、测试名）。

**3) 机制类型**：子 agent 并行（按证据类别）+ 多模型 + MCP 发现。依赖 Cursor：`readonly: false` 才能用 MCP（`SKILL.md:13`）、`mcps/` 目录做发现（`:35`）、`pstack-models.mdc`。

**4) Claude Code 映射**：可实现。
- MCP 发现：Claude Code 主线程能看到已连接 MCP 的工具名（含 deferred 工具清单），可直接映射；`general-purpose` 子 agent 拥有全部工具，可用 MCP（是否继承所有 MCP 连接需实测，**推测**可以）。
- 用户当前环境实际只有 git/gh、Claude Docs、pencil 等，**7 类里通常只有“源码史”可用**。因此在该用户这里，why 在 Claude Code 上的真实形态是：主线程建锚点 + 1 个源码考古 investigator（或直接内联）+ 主线程按 epistemics 写结论。并行 7 路的架子基本空转。
- synthesizer 可用 `model: "opus"`；也可由主线程直接承担（省 1 次调用，代价是主上下文变大）。

**5) 成本**：理论 2–8 个子 agent（1–7 investigator + 1 synthesizer）；该用户实际 1–2 个。

**6) devflow 对应物与差距**：D **没有对应物**。`devflow-research/SKILL.md:19` 要求“为每个关键设计解释它解决的问题和代价”，`references/report-template.md:28-33` 有“为什么”字段——但这恰恰是 P 明令禁止的“从代码反推意图”。D 不查 git blame / PR / 工单，也没有置信分级。这是本组最大的差距。

**7) 判断：改写后采用。** 照搬 epistemics（五级置信 + “代码不证明意图” + 附和陷阱 + 空结果也报）和 code-archaeology 命令清单；砍掉 7 类 MCP 并行骨架，改成“有什么源就查什么源，源码史必查”，默认内联或 1 个子 agent。

---

## 3. 让我真正理解（教学） —— `/teach`

**1) 问题**：摘要不够，我想真正懂一个子系统或一次改动，并能和讲解者来回追问。

**2) pstack 解法**
- 触发：`/teach ...`（`skills/teach/SKILL.md:1-5`）。
- 步骤：先定 2–3 个“要带走的点”，从对话推断用户目的，不考问用户（`:13`）；主线程先自己读代码定向，再**并行调用 how 与 why 两个技能**，小改动可只调一个，why 默认收窄（`:14`）；先给通俗定义再落到本例（`:15`）；保持对话式、一次只给最小完整答案（`:15-16`）。
- 关键规则：
  - 禁止“教学表演”：不说“关键是”“TL;DR”“这是难点”，不出小测验（`:15-16`）。
  - **图要逐步搭建**：三个以上部件时画一组图，每张在上一张基础上只加一个部件，不要一张全景图放最后（`:17`）。空间类概念调用图像生成工具画白板风格图（`:17`）。
  - 写作风格：经 unslop，句号优于逗号，一个概念一个名字，不用破折号（`:19`）。
  - 保留 why 的置信措辞（`:11`）。
- 指南里的用法提示：“convince me it fixes the cause and not the symptom”把讲解变成可反驳的论证（`docs/guide/03-understand.md:40-43`）；也可让 agent 解释它自己的实现取舍（`:47-51`）。

**3) 机制类型**：纯提示词编排（组合 how + why 两个技能）+ 依赖 Cursor 的图像生成工具。

**4) Claude Code 映射**：可实现。技能调用技能在 Claude Code 里通过 Skill 工具串行加载（Skill 内容进入主上下文），**并行**需要把 how、why 各包成一个 `general-purpose` 子 agent 并让它们在内部加载技能（**推测**可行，但嵌套子 agent 在 Claude Code 里受限：子 agent 默认不能再派子 agent，所以 how 的复杂路径在子 agent 内会退化为单 agent）。图像生成：Claude Code 没有原生工具，用 Mermaid/ASCII 逐步图代替，或用 Artifact 发布内联 SVG 页面（`artifact-diagramming` 技能）。

**5) 成本**：how（1–5）+ why（1–8）；该用户实际 2–4 个子 agent。

**6) devflow 对应物与差距**：D 无专门技能。`devflow-research/references/report-template.md:44-45` 有“通俗类比”节；`references/diagrams.md:24` 限制单图约 15 节点，但没有“逐步搭建”的教学规则；D 默认产出是一份完整文档，不是对话式渐进讲解。

**7) 判断：改写后采用，但并入 research 而非单独成技能。** 值得吸收的是两条规则：“先给最小完整答案再按追问加层”和“图逐步搭建”。单独一个 teach 技能会和 research 抢触发词。

---

## 4. 找回我自己的历史上下文 —— `/recall`（含 Session pickup）

**1) 问题**：隔了几天回到某个主题，想知道我之前做到哪、决定了什么、哪些修复被回滚过、下一步做什么。

**2) pstack 解法**
- 触发：`/recall ...`；“恢复某个具体会话”走 Session pickup playbook 而不是它（`skills/recall/SKILL.md:17`、`docs/guide/03-understand.md:65-75`）。
- 步骤（`skills/recall/SKILL.md:17-22`）：分类与路由 → 锁定范围（默认最近 7 天、当前工作区，绝不读别的项目，`:18`）→ **按语料切片并行派快模型子 agent 挖自己的聊天记录**，按真实 mtime 排序、先 grep 主题再只读命中片段、跳过当前会话和子 agent/eval 会话，统一返回 schema 并引用 UUID（`:19`）；1–2 个会话则不分派 → 主题涉及功能/文件/子系统时**默认**同时跑 why 的各源 investigator，问题改为“现状、试过没成功的、用户还在报什么”（`:20`）→ 用 git/gh 核对 PR、分支、工单的实时状态（`:21`）→ 按契约写简报。
- 关键规则：输出契约 Capsule ≤5 条、每条线索恰好一个状态标签 `[merged #N]` / `[open PR #N]` / `[in flight <branch>]` / `[verified, uncommitted]` / `[reverted #N]` / `[planned, not started]`、Problems ≤5、Next move 一条（`:26-31`）；聊天发现引 UUID、共享记录引来源（`:33`）。
- Session pickup：先读元数据和末尾消息，再回溯决策点，长 transcript 交给子 agent 解析（`playbooks/session-pickup.md:5`）；前人记录是权威输入，不要“从头验证一遍”（`:6-7`），但继承的结论要在真实产物上验证（`:9`）。

**3) 机制类型**：子 agent 并行（按会话切片）+ 复用 why investigator + 脚本式 git/gh 核对。依赖 Cursor：transcript 路径 `~/.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>.jsonl`（`skills/recall/SKILL.md:15`）。

**4) Claude Code 映射**：可实现，路径需改。
- Claude Code 的会话记录在 `~/.claude/projects/<slug>/<uuid>.jsonl`，`<slug>` 是工作区路径把 `/` 换成 `-`（**保留开头的 `-`**，例如本项目是 `-Users-lionoggo-Workspaces-devflow`，已在本机观察到）；子 agent 的记录在同级 `<uuid>/` 目录下（**推测**，需确认目录结构）。
- 切片子 agent 用 `Explore` + `model: "haiku"`。
- 部分重叠的原生能力：`claude --resume` / `--continue` 恢复单个会话；该项目已有 `memory/` 目录（auto-memory）。
- 用户只有 git/gh，共享记录扫描基本等于 `git log` + `gh pr list/view`。

**5) 成本**：0–5 个子 agent（会话少时 0）+ why 的 1–2 个。

**6) devflow 对应物与差距**：D 无 recall。最接近的是 `devflow-impl/references/handoff.md`（写交接 prompt，且明确不带 transcript，`handoff.md:73`）和 devflow-autorun 的日志。D 解决的是“主动交接”，P 解决的是“事后从记录里重建”，后者 D 完全没有。

**7) 判断：改写后采用（优先级中等）。** 状态标签契约和“只读当前工作区 + 按 mtime + 先 grep”规则可以照搬；路径改为 `~/.claude/projects/`；共享记录扫描缩成 git/gh。

---

## 5. 复述目标 —— `/in-your-own-words`

**1) 问题**：动手前确认 agent 真的理解了我要什么。

**2) pstack 解法**：整个技能就一句话：“用你自己的话复述用户的目标和要解决的问题”（`skills/in-your-own-words/SKILL.md:7`）。用户手动调用。

**3) 机制类型**：纯提示词。

**4) Claude Code 映射**：直接可用，零成本。

**5) 成本**：0 子 agent。

**6) devflow 对应物**：`devflow-plan/SKILL.md:20-23,79-84` 的需求阶段“我的理解 / 现状 / 你提到的做法 / 需要你确认”已覆盖，且更结构化（区分需求和手段）。

**7) 判断：不需要。** D 的需求阶段已经更好。

---

## 6. 只读调查的总路由 —— Investigation playbook

**1) 问题**：我只想要结论和证据，不想 agent 顺手改代码。

**2) pstack 解法**：只读，产出有引用的解释或带权衡表的建议（`playbooks/investigation.md:5`）；走 how，动机类再走 why（`:7`）；输出 how 结构，若是二选一的决策则给权衡表（`:9`）；不开 PR、不跑 architect，若要改代码交还用户重新路由（`:12`）；对“are we sure?”给真实判断，前提错了要反驳（`:14`）。指南里推荐的提示词是“给我已知、用了什么数据、最佳假设，先别改代码”（`docs/guide/03-understand.md:11-17`）。

**3) 机制类型**：纯提示词路由（依赖 poteto-mode 总入口）。

**4) Claude Code 映射**：可实现。由于 D 是描述触发，这层路由对 D 意义不大，规则直接写进 research 技能即可。

**5) 成本**：等于 how(+why)。

**6) devflow 对应物**：`devflow-research/SKILL.md:8`（只读）和 `:30-31`（变成 debug/plan 问题时停在定位）已覆盖。差距只有“决策型问题给权衡表”这一条。

**7) 判断：不需要单独采用。** 把“决策型问题输出权衡表并推荐”一句并入 research 或 plan 即可。

---

## 7. 设计方案探索与定形 —— `/architect`

**1) 问题**：非平凡改动，我不想让 agent 拿第一个想到的形状直接写代码，想先把类型、签名、模块边界定下来。

**2) pstack 解法**
- 触发：`/architect`；poteto-mode 规定“跨函数边界的代码”自动触发（`skills/poteto-mode/SKILL.md:22`）。
- 五阶段（`skills/architect/SKILL.md:13-19`）：
  - A Ground：跑 how 建模型，改所有权/分层时再跑 why，把历史理由变成约束（`:21-25`）。
  - B Sketch：调 arena，每个 runner 用 `runner-prompt.md`，runner 来自 `architect runners` 配置（默认 opus + grok）（`:27-31`）；**至少两个结构上不同的候选**（`:33`）；每个候选过一遍 design-red-flags，并假设“下一个贡献者是只看得到自己打开的文件、复制最近示例、走最短编译路径的 agent”（`:35`）；按接口深度比较（`:37`）。
  - C Agree：**默认不设人工检查点**，直接进实现；用户明确要求才停（`:41-45`）；可用 interrogate 加压（`:47`）。
  - D Implement：草图就是契约，偏离要上报而不是悄悄吸收（`:51-53`）。
  - E Scrap：同类 workaround 反复出现、类型需要逃生舱、出现“需要加锁”反射等模式化信号时推倒重来，先做减法再回 B（`:55-75`）。
- 关键规则：
  - 先写调用方用法，再从用法推导类型（`:79`、`references/rationale-template.md:9-11`、`runner-prompt.md:9`）。
  - 7 个设计红旗：浅模块、信息泄露、时序分解、透传方法、所有权分裂、一件事两种做法、内部可被导入、手工同步的列表（`references/design-red-flags.md:5-57`）——后四条专门针对“AI agent 作为后续维护者”。
  - runner 不要互相对冲，求差异（`runner-prompt.md:20`）。
  - 理由文档模板：Problem / Usage / Shape / Synthesis decision / Tradeoffs / Alternatives（必填）/ Open questions / Next step（`rationale-template.md:5-35`）。

**3) 机制类型**：技能编排（how + why + arena）+ 子 agent 并行 + 多模型 + 可选 worktree 隔离。依赖 Cursor：`pstack-models.mdc` 的 architect runners、Task model。

**4) Claude Code 映射**：可实现，需两处改动。
- 多候选：2 个 `general-purpose` 子 agent，`model: "opus"` 各一，或一个 opus 一个 `codex exec`（跨家族；**推测**用 `codex exec -s read-only "<prompt>"` 在后台 Bash 跑，产出写到 scratchpad 下各自目录）。不必用 worktree：草图是类型和签名文件，放在 scratchpad 的 `candidate-1/`、`candidate-2/` 即可，符合用户“不建 worktree”的规则。
- 人工检查点：用户 AGENTS.md 要求方向由用户决定，应把 C 阶段改成**默认停下**让用户选，和 D 的“方向待你选择”对齐。

**5) 成本**：how 1–5 + why 0–2 + arena（2 runner + 1 judge）≈ 4–10 次子 agent 调用，外加实现。对小改动明显过重。

**6) devflow 对应物与差距**：
- `devflow-plan/SKILL.md:35-43` 的方向阶段（比较可信方向、倾向最小可逆、新增契约/持久状态/服务要说明为何现有边界不够、用户选）；`references/plan.md:44-62` 的架构节（Components / Contracts / Dependency direction / Runtime flow / State / Invariants / Change map）。
- D 缺的：①“先写调用方用法”这一硬规则；②产出**真实的类型/签名草图文件**（D 只有文字计划）；③“至少两个结构不同的候选”的强制；④面向 agent 维护者的红旗清单；⑤实现中的“推倒重来”信号。
- D 更好的：用户确认方向；“最小可逆”偏好；readiness 五问（`plan.md:64-82`）。

**7) 判断：改写后采用。** 把 usage-first、红旗清单、Alternatives 必填、Scrap 信号并入 devflow-plan 的方向/架构部分；“双候选并行”作为高风险设计的可选项，而不是每次跨函数边界都跑；检查点保持默认开启。

---

## 8. 多候选并行择优 —— `/arena`

**1) 问题**：一个难的产物（设计、命名、格式、算法），一次尝试容易锁死在第一个形状上，我想要几个独立版本然后取长补短。

**2) pstack 解法**
- 触发：`/arena`；architect 的 B 阶段；eval playbook 的候选与评审（`playbooks/eval.md:20-21`）；blast-radius 大改动时（`skills/blast-radius/SKILL.md:38`）。
- 六阶段（`skills/arena/SKILL.md:9`）：
  - Frame：提示词就是契约；为本任务定 3–6 条可打分 rubric，**只给 picker 不给候选**（`:13-16`）；runner 来自配置，默认 opus + grok 各一，生成型任务可同模型跑 N 次（`:17`）；每个候选独立输出位置，优先 worktree（`:18`）。
  - Fan out：同一条消息后台派出；掉一个就 N-1 继续（`:22-24`）。
  - Cross-judge：候选全部完成后，选一个**与父模型不同家族**的只读评委，按 rubric 打分并推荐 base，与主线程阅读并行（`:28`）。
  - Pick：主线程逐条读完每个候选、逐条打分，与评委对比；分歧意味着有偏或 rubric 含糊（`:32`）；平手选边界更干净、API 更小的（`:34`）。
  - Graft：每个落选者通常只移植 1–2 点，手工融入而非粘贴（`:38`）；候选收敛则直接用共识；严重发散说明 Frame 欠定义，应重来而不是取平均（`:40`）。
  - Verify：按 prove-it-works 验证（`:44`）。
- 输出：合成产物 + 说明（base 及理由、评委结论、每个移植及来源、拒绝项、掉队、验证结果）（`:48`）。

**3) 机制类型**：子 agent 并行 + 多模型（跨家族评委是核心设计）+ worktree 隔离。依赖 Cursor：Task model、`pstack-models.mdc`。

**4) Claude Code 映射**：可实现，跨家族是难点。
- 候选：`general-purpose` × N，`run_in_background: true`，输出到 scratchpad 子目录（替代 worktree）。需要改代码的候选才需要隔离；Agent 工具有 `isolation: "worktree"`，但用户规则禁止未经明确要求创建 worktree，所以默认用目录隔离，代码类候选需先问。
- 跨家族评委：`codex exec`（只读沙箱）读取各候选目录并按 rubric 打分（**推测**可行，需实测 codex 能否读取 scratchpad 路径和输出长度）。没有 codex 时退化为不同档位 Claude（opus 候选 + sonnet 候选，fable 评委等），信号会变弱，应在输出里说明。
- 用户 CLAUDE.md 对 Fable 的限制（只用于重大架构方案起草）要遵守：评委默认 opus。

**5) 成本**：N 个候选（≥2）+ 1 个评委 + 主线程完整阅读所有候选（主上下文消耗大）。典型 3 次子 agent 调用。

**6) devflow 对应物与差距**：无。最接近的是 `devflow-plan/references/review.md:12-16` 的 independent 模式（另一会话或模型审查**一个**方案），那是“审查”不是“竞标”。

**7) 判断：改写后采用，作为按需工具而非默认流程。** rubric 不给候选、跨家族评委、“发散则重新 Frame 不要平均”、“每个落选者只移植 1–2 点”这几条规则很扎实；但成本高，只用于不可逆、贵的决定（指南也这么说，`docs/guide/04-design.md:125,128`）。

---

## 9. 并行覆盖 / 竞速 —— `/swarm`

**1) 问题**：同一检查要跑在很多包/场景上，或几个方案比谁先过，我要一份汇总报告。

**2) pstack 解法**
- 四阶段（`skills/swarm/SKILL.md:13-18`）：
  - Frame：完成谓词和产物；形状是切片、竞速或混合，竞速要先声明 `first pass` / `rank all` / `best-of`（`:22-23`）；N 是总 worker 数（`:24`）；度量类任务写明 SHA 和方法（样本数、单样本定义、顺序）（`:26`）。
  - Fan out：同一条消息派出，`environment: "cloud"`，后台运行（`:30`）；每份 brief 自足，报告用 `PASS` / `ISSUES` / `BLOCKED` 加证据，ISSUES 要列出全部可证明问题（`:34`）。
  - Aggregate：缺 SHA/方法的结果丢弃并重派一次，再缺记为 gap，**gap 不算通过**（`:40`）；不贴原始输出。
  - Report：一张表 + 一行一个问题 + 缺口（`:46`）。
- 与 arena 区别：swarm 不做 base 选择和移植（`docs/guide/04-design.md:61`）。multi-phase plan 里每个 PR 的 live 验证是 10 条 swarm lane（`playbooks/multi-phase-plan.md:13`）。

**3) 机制类型**：子 agent 并行。依赖 Cursor：**云端子 agent**（`environment: "cloud"`、`cloud_base_branch`，`:30-32`），每个 worker 一台云 VM。

**4) Claude Code 映射**：本地版可实现。`general-purpose`/`worker` × N，`run_in_background: true`，同一条消息派出。云端 VM 无直接等价：Agent 工具 `isolation: "remote"`（受限可用）或 `/schedule` 云 routine 可部分替代，**推测**都不适合一次 10 路并发。本地并发受机器资源和端口冲突限制。

**5) 成本**：N 个子 agent（N 由切片数决定，常见 3–10）。

**6) devflow 对应物与差距**：`devflow-impl/references/delegation.md:3-11`（默认不委派、只读 worker 便宜、写入需不相交范围）；`devflow-verify/SKILL.md:32-35`（只读验证子 agent）；devflow-autorun（串行契约循环）。D 没有“扇出 + 统一 PASS/ISSUES/BLOCKED + gap 不算通过”的汇总规程。

**7) 判断：改写后采用（轻量）。** 只吸收报告契约（三态 + 证据 + gap 不算 pass + 度量任务写 SHA 和方法）放进 verify/impl 的委派说明；不单独建 swarm 技能，也不追求云端 10 路。

---

## 10. 方案 / 代码对抗审查 —— `/interrogate`

**1) 问题**：改动写完了，我想让“不同脑子”尽力找出真实问题，再由一个务实的负责人筛掉噪音。

**2) pstack 解法**
- 触发：`/interrogate`；poteto-mode 规定“有争议的设计”上线前触发（`skills/poteto-mode/SKILL.md:24`）；architect 可选（`skills/architect/SKILL.md:47`）。
- 步骤（`skills/interrogate/SKILL.md:11-51`）：确定范围（默认 `git diff main...HEAD`）→ **一段话写清意图，不确定就问用户**（`:21-23`）→ 每个配置的模型一个审查者，同一条消息派出，只读（`:25-38`）→ 合并重复发现，标注由哪些模型提出，“两个以上模型独立提出”为最高信号（`:40-42`）→ 主线程作为“务实的资深工程师”分四档：Act on / Consider / Noted / Dismissed（`:44-51`）。不自动改代码（`:9`）。
- 关键规则：
  - **对抗信号来自模型多样性而不是人设**（`:9`）。
  - 审查者：不质疑意图、只挑执行；严重度 critical/warning/nit；必须有证据；可以“无发现”（`references/reviewer-prompt.md:15,35-45`）。
  - rubric：正确性（含幂等、并发）、根因 vs 症状、结构完整性（含遗留双路径）、可验证性（“查真东西不是代理”）、复杂度预算、安全（`references/rubric.md:5-77`）。
  - 代码质量镜头：“code judo” 结构性简化、文件从 <1k 行涨到 >1k 行视为强烈异味、不要在无关流程里加 ad-hoc 分支（`references/code-quality-review.md:21-35,41-43`）。
  - 负责人判断：nitpick 引力、假设性 vs 实际（要追调用点）、过早抽象、“我会换种写法”是最常见误报、缺上下文信号；Act on 超过 5 条说明筛得不够；Dismissed 一节是信任机制（`references/lead-judgment.md:16-58`）。
  - 指南明确：**不要拿 interrogate 审没有代码的抽象计划**，审查者会编造理论风险（`docs/guide/04-design.md:89`）。

**3) 机制类型**：子 agent 并行 + **多模型（核心）**。依赖 Cursor：Task model、`pstack-models.mdc`。

**4) Claude Code 映射**：可实现，有两条路。
- 原生：Claude Code 内置 `/code-review` 技能（多档 effort，`ultra` 为云端多 agent 深度审查）和 `/simplify`（质量清理）。它们覆盖“找 bug”，但不提供跨家族信号，也没有 P 的四档判决格式。
- 自建：审查者 A = `general-purpose` + `model: "opus"`；审查者 B = `codex exec`（只读）喂同样的 diff + rubric（**推测**，需实测 codex 输出格式稳定性）；主线程按 lead-judgment 分档。这是本组跨模型最划算的落点：只有 2 次调用、输入是一份 diff，输出短。

**5) 成本**：2 个审查调用（1 Claude 子 agent + 1 codex）+ 主线程综合。

**6) devflow 对应物与差距**：
- `devflow-plan/references/review.md`：审查**计划**，self/subagent/independent 三档，P0/P1/P2，adopt/defer/reject，最多两轮（`:6-21,30-49`）。
- `devflow-verify/SKILL.md:32-35`：只给验收标准和候选的只读验证者。
- 差距：D 没有针对**代码 diff** 的对抗审查；没有“多模型共识 = 高信号”；没有 Dismissed 一节；没有 code-quality 镜头。另一方面，D 的 review.md 审的是计划，与 P 指南 `04-design.md:89` 的观点相反——值得重新考虑 D 的计划审查是否容易产出“理论风险”。

**7) 判断：改写后采用（高优先级）。** rubric、code-quality 镜头、lead-judgment 几乎可照搬；审查者改为 1 个 opus 子 agent + 1 个 codex；可以作为 devflow-verify 的一种模式，或单独的 `devflow-review`。

---

## 11. 改动影响面 —— `/blast-radius`

**1) 问题**：这个 diff 看着小，但我不放心，它会在 diff 之外弄坏什么？

**2) pstack 解法**
- 触发：`/blast-radius`（`skills/blast-radius/SKILL.md:1-5`）。
- 核心思想：“列调用方不是工作，grep 一秒就有；工作是 grep 看不到的破坏”（`:13`）；“听起来对的影响面报告毫无价值，要证明”（`:17`）。
- 证据五级：你说的 → 指到行 → 走查证明坏情况到不了 → **跑过（调用真实代码的脚本或测试）** → 在运行的应用里复现（`:19-29`）。
- 步骤（`:31-38`）：读改动（借 why step 2 拉 PR）→ **找出“它安全是因为哪一个事实”**，在这上面花时间而不是列一长串可能性（`:34`）→ 看 grep 停止的地方：库源码及其锁定版本和本地补丁、执行时机（微任务、卸载）、JSON/DB 列/线协议/另一种语言读同一份字节/特性开关/三跳之外（`:35`）→ 每个风险给概率和代价，确认的和排除的分开列（`:36`）→ 写脚本跑真实代码证明那个事实（`:37`）→ 大改动用 arena 多模型（`:38`）。
- 输出：它做了什么 / 安全依赖的那个事实（已证明到第几级，否则写 unproven）/ 风险 / 已排除 / 合并前最便宜的检查（`:40-46`）。

**3) 机制类型**：纯提示词 + 脚本（主线程写验证脚本），大改动时可选多模型。不依赖 Cursor 特性。

**4) Claude Code 映射**：直接可实现，零改造。主线程用 Bash 跑证明脚本即可。

**5) 成本**：默认 0 个子 agent；大改动 arena 时 +3。

**6) devflow 对应物与差距**：无专门技能。`devflow-plan/references/plan.md:76-79`（readiness 第 4 问“Claim strength”：启动只证明能启动，存在只证明被生成；能否有更便宜的违规实现也通过）在精神上接近“证明那一个事实”，但用在计划阶段。`devflow-verify` 关注验收标准而不是 diff 之外的破坏。

**7) 判断：照搬（小幅本地化）。** 成本低、无平台依赖、与 D 的“证据要与主张同级”理念一致，补上了 D 完全缺失的“改动前影响面”环节。去掉对 Solid/React 的特定举例即可。

---

## 12. 用原型代替争论 —— Prototype playbook

**1) 问题**：两种方案各有道理，与其讨论或问我，不如做出来看。

**2) pstack 解法**
- 触发：poteto-mode 的核心规则——准备问“哪种方法”之前先分类：**能通过运行观察到的事实不该问人**，去做原型（`skills/poteto-mode/SKILL.md:20`）；用户说 prototype / mock it up 时（`:133`）。
- 步骤（`playbooks/prototype.md:7-12`）：先界定原型要做的那个决定，没有决定就不做原型 → 设计空间开放时先收集参考 → 在隔离的 scratch 目录里做一次性实现，视觉用原生 HTML/CSS/JS，行为/时序用最小脚本，不要框架、测试、抽象 → 多方案放在一个切换器后面 → 在匹配的界面上验证（截图、日志、计时），“观察本身就是测试” → 输出方案、证据、取舍、推荐和 scratch 路径，明确说是一次性的。
- 关键规则：这是唯一“最小改动”和验证门槛反转的 playbook，速度优先，代码质量不重要（`:5`）。

**3) 机制类型**：纯提示词。依赖 Cursor：截图依赖 `cursor-team-kit` 的 `control-ui` / `control-cli` 控制技能（`:11` 的 “control skill”，见 `playbooks/multi-phase-plan.md:15`）。

**4) Claude Code 映射**：可实现。scratch 目录用 Claude Code 的 scratchpad；视觉对比可用 Artifact 发布一个带切换器的 HTML 页面（私有），或用浏览器/Computer Use 技能截图（`anthropic-skills:chrome-browser`、`built-in-browser`）。CLI 行为用 Bash 直接跑。

**5) 成本**：0 子 agent，主线程若干次运行。

**6) devflow 对应物与差距**：D 没有。`devflow-plan/SKILL.md:31-32` 说“不要问仓库能回答的事实”，方向更窄（只限读仓库）；`devflow-research/references/html-demo.md` 是解释用的演示，不做决策。D 的方向阶段只做“纸面比较”。

**7) 判断：改写后采用。** 把“问用户前先分类：能跑出来的就跑”加入 devflow-plan 的方向阶段，并给一个 prototype 参考文件（scratchpad、一次性、多方案同屏、观察即证据）。但要和用户规则协调：产品/偏好类决定仍归用户。

---

## 13. 计划成文与结构校验 —— Multi-phase plan playbook + `check-plan.mjs`

**1) 问题**：跨多个 PR 的工作，我要一份每一项都带证据、可以逐项打勾审计的计划。

**2) pstack 解法**
- 指南：pstack **刻意没有规划技能**，设计定了再写计划（`docs/guide/04-design.md:103`）。
- 步骤（`playbooks/multi-phase-plan.md:5-11`）：一两个文件、做法显然时跳过计划 → 先用 prototype 解决开放问题，只在没有实验能回答的产品/偏好问题上问人 → 用 `poteto-agent` 子 agent 探索，只回文件指针、约定、测试命令、入口，不回原文 → 填骨架，一个 PR 一节 → 用 technical-writing 和 unslop 写 → **运行 `check-plan.mjs` 并修掉它打印的每一行** → 交回路径和脚本输出后停下，等明确的“开始”。
- 骨架要点（`:17-153`）：开头 ≤10 行；“How to read this”说明一个框是一个工作单元、每个框写明证据；Program checklist（Arm / Spawn owners / PR mechanics / Verdict and merge / Boot recipe，含 `/loop 1h` 审计 tick 原文提示词 `:41-42`）；每个 PR 节固定 9 个子块 Depends on / Files / Build / You see / Verify unit / Verify live（**10 条 lane**，每条要截图和通过谓词）/ Verify perf（Metric / Probe / Baseline / Rule，主干和 head 交错测）/ Review gate（截图 + 视频）/ Merge；附录 A 原型证据必有。
- 验证规则：“只有测试不算验证”，每个验证块必须以这句开头（`:13`）。
- `check-plan.mjs`（`skills/poteto-mode/scripts/check-plan.mjs`）：纯 Node 静态检查。正文禁长破折号、弯引号、句中冒号（`:78-80`）；H1 存在、开头 <10 行（`:94-100`）；How to read this 必含 5 个标记（`:21-27,101-103`）；Program checklist 的 5 个 H3 按序出现且含 `git show origin/main:`、`/loop 1h`、`status message`（`:19-20,106-119`）；每个 PR 节 9 个子块顺序严格一致（`:138-140`）；三个验证块以规则句开头（`:151-154`）；live 恰好 Lane 1–10，每条有截图和 `Pass when`（`:156-167`）；perf 四项按序（`:169-173`）；Review gate 为 None 时不能有框，否则要含 screenshot/video/operator（`:175-187`）；Close 之后只能是附录且必须有 Prototype evidence（`:194-200`）。输出每节框数统计（`:189-191`），有问题退出码 1。

**3) 机制类型**：提示词模板 + **脚本校验**（无模型调用）。依赖 Cursor：`poteto-agent` 自定义 agent、`cursor-team-kit` 的 control-ui/control-cli、云端 VM lane、Bugbot、Origin forge、`/loop 1h`、`/deslop`。

**4) Claude Code 映射**：
- 校验脚本思路完全可移植（Node 或 shell 均可），但**规则本身必须重写**：P 的 10 lane / 视频 / Bugbot / 云 VM / 句中冒号规则（中文写作也不适用）都不适合用户。
- `/loop` 在 Claude Code 有原生 `loop` 技能；用户的 devflow-autorun-tick 已经基于 `/loop`。
- `poteto-agent` → 用户已有的 `~/.claude/agents/explorer.md`。

**5) 成本**：写计划阶段 1–3 个探索子 agent + 若干原型；脚本 0 调用。P 计划**执行**的成本极高（每 PR 10 条 live lane + perf lane + ≥2 审计 lane 的 swarm，`:65`）。

**6) devflow 对应物与差距**：
- `devflow-plan/references/plan.md`：Core Plan（Goal / Non-goals / Decisions / Open decisions 必须为 none / Acceptance A/E 项 / Scope / Risks，`:9-20`），证据要与主张同级（`:33-35`），按需分阶段，autorun 契约拆分表 `| 契约 | 写入范围 | 完成条件命令 | 预算 |` 和人工项表（`:38-42`），readiness 五问（`:64-82`），证据偏好（`:84-91`）。
- D 比 P 更适合用户：随改动规模缩放、中文、不绑定 PR 流程、已和 devflow-autorun 衔接。
- D 缺的：**没有机器校验**。“Open decisions 必须为 none”“每条验收必须写验证方法”“契约表每行都有完成条件命令”这些都是可以脚本化的硬约束，现在只靠模型自觉。P 的 encode-lessons-in-structure 原则（`skills/poteto-mode/SKILL.md:79`）正是这一点。

**7) 判断：模板不需要，校验脚本思路改写后采用。** 为 D 的 plan.md 写一个 `check-plan.sh`（或并入 devflow-autorun 的 arm 前检查）：检查 Open decisions 为 none、每个 A 项含“verify with/验证”、契约表列完整、人工项表格式。模板本身保留 D 的。

---

## 14. 评测技能/提示改动 —— Eval playbook

**1) 问题**：我改了一个技能或提示，想知道它是否真的改变了 agent 行为，而不是凭感觉。

**2) pstack 解法**（`playbooks/eval.md`）：
- 盲测硬规则：候选能看到的目录、文件、提示里不得出现 eval/test/judge/rubric/arena 等词；提示像真实用户请求；不诱导自报用了哪些技能；不告诉候选有其他候选；评委只看脱敏标签不看模型名；两个变体用同一评委一次打分（`:5-13`）。
- 步骤：定 rubric（只给评委）→ 每个候选独立脱敏目录 → 一条“自然”的提示 → 按 arena Phase B 并行候选 → 按 arena Phase C 跨家族盲评 → **从 transcript 验证候选实际读了哪些文件**，不信自报，且不跨工作区读 transcript（`:22`）→ 主线程逐个读完并与评委对比（`:17-23`）。

**3) 机制类型**：子 agent 并行 + 多模型 + 依赖 Cursor 的 agent-transcripts 路径。

**4) Claude Code 映射**：部分可行。候选用子 agent，transcript 在 `~/.claude/projects/<slug>/` 下可读（**推测**子 agent transcript 能定位到）。但“候选在脱敏目录里像真实用户一样被触发技能”在子 agent 里很难做到——子 agent 的技能可见性由父会话环境决定；更可靠的做法是 `claude -p` 在独立临时目录里跑（**推测**），或用内置的 `skill-creator` 技能（含 eval/benchmark 功能）和 `claude plugin eval`。

**5) 成本**：N 候选 + 1 评委，外加环境搭建。

**6) devflow 对应物与差距**：D 有 `test.sh` 跑各技能 `scripts/*-test.sh`（只测脚本，不测模型行为）。没有行为级评测。

**7) 判断：改写后采用（低优先级）。** 盲测规则（不泄露“在测试”、不信自报、从 transcript 查实际读取）很有价值，适合用户在重建 devflow 时验证新技能；但实现应优先用 Claude Code 现成的 skill-creator / plugin eval，而不是手搓 arena。

---

## 15. 本组总结

### 最值得采用的 3 点

1. **why 的认识论框架**（`skills/why/references/epistemics.md` 全文 + `sources/code-archaeology.md`）：五级置信、“代码不能证明自身意图”、不附和用户自带的假设、空结果也报、改代码前转成 Preserve/Change/Avoid/Risk。它直接修正了 D 当前“从代码反推‘为什么’”的做法（`devflow-research/SKILL.md:19`），且在用户只有 git/gh 的环境下几乎零成本（主线程内联即可）。
2. **interrogate 的“多模型审查 + 务实负责人分档”**（`skills/interrogate/references/rubric.md`、`code-quality-review.md`、`lead-judgment.md`）：D 缺少针对代码 diff 的审查。在 Claude Code 上用 1 个 opus 子 agent + 1 个 `codex exec` 就能拿到跨家族信号，成本只有 2 次调用；Dismissed 一节和“Act on 超过 5 条说明筛得不够”是很好的降噪机制。
3. **blast-radius 的“找到安全依赖的那一个事实并跑代码证明”**（`skills/blast-radius/SKILL.md:15-38`）：无平台依赖、0 子 agent，可直接照搬，补上 D 缺失的“改动前影响面”环节。并列第 4：architect 的 usage-first + 面向 agent 维护者的设计红旗（`references/design-red-flags.md`），以及 check-plan 式的“把计划规则编码成脚本”。

### 最不值得采用的 3 点

1. **multi-phase-plan 的计划模板本身**（10 条 live lane、视频审查门、Bugbot、云 VM boot recipe、Origin forge）：深度绑定 Cursor 云端 agent 和 PR 流水线，执行成本极高；D 的 plan.md 更适合用户。只拿校验脚本的思路。
2. **swarm 的云端扇出**（`environment: "cloud"`、`cloud_base_branch`）：Claude Code 没有可靠等价物，本地 N 路并发受资源限制；只需吸收 PASS/ISSUES/BLOCKED + “gap 不算通过”的报告契约。
3. **architect 默认无人工检查点 + 每次跨函数边界都跑 arena**（`skills/architect/SKILL.md:43`、`skills/poteto-mode/SKILL.md:22`）：与用户“方向由用户决定”“只在实质降低成本时用子 agent”的规则直接冲突，一次 4–10 个子 agent 对日常改动太重。in-your-own-words 也不需要（D 的需求阶段已覆盖）。

### 附：平台映射速查

| pstack / Cursor | Claude Code | 备注 |
|---|---|---|
| Task `generalPurpose` | Agent `general-purpose` | |
| Task `readonly: true` | Agent `Explore` 或 `~/.claude/agents/explorer.md` | |
| `poteto-agent` | `~/.claude/agents/worker.md` / `explorer.md` | 用户已有 |
| `model: claude-opus-5-5-xhigh` | `model: "opus"`（effort 不可单独设，除非用户要求） | |
| `model: grok-*` / 跨家族评委 | `codex exec`（后台 Bash） | 推测，需实测参数与输出 |
| `pstack-models.mdc` | 技能内写默认值；或 `~/.claude/CLAUDE.md` 一节 | 用户 CLAUDE.md 已有模型分级规则 |
| `environment: "cloud"` | `isolation: "remote"` / `/schedule` | 受限，不建议依赖 |
| arena 的 worktree | scratchpad 子目录；代码类候选需用户同意后 `isolation: "worktree"` | 用户规则禁止擅自建 worktree |
| `agent-transcripts/<uuid>/<uuid>.jsonl` | `~/.claude/projects/<slug>/<uuid>.jsonl` | slug 保留开头 `-`，已观察 |
| AskQuestion | AskUserQuestion | |
| todolist | TodoWrite | |
| `/loop 1h` | `/loop`（原生技能） | devflow-autorun-tick 已在用 |
| 图像生成（teach 白板图） | Mermaid / ASCII / Artifact 内联 SVG | 无原生图像生成 |
| control-ui / control-cli（cursor-team-kit） | chrome-browser / built-in-browser / computer-use 技能、Bash | |
| interrogate | 内置 `/code-review`（单家族）+ 自建 codex 审查者 | |
