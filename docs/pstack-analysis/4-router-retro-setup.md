# pstack 分析 · 场景组 4：入口路由、原则体系、复盘与定制、安装配置

## 结论先行

- pstack 的核心不是那 30 多个技能，而是三件事：**单一显式入口**（`/poteto-mode`，把匹配到的剧本步骤原文抄进 todo）、**可按名字引用的原则词表**（24 条，单条很短，用来“一句话转向”），以及**把反复出现的错误变成结构**的闭环（`/correct` 改仓库，`/reflect` 改技能，eval 防止技能越改越偏）。这三件事在 Claude Code 上都能实现，不依赖 Cursor。
- 和 Cursor 绑定、在 Claude Code 上要重做或放弃的部分：Custom Mode 常驻、`pstack-models.mdc` 按角色配置模型、多模型家族评审面板（Opus + Grok）、`create-skill`/`deslop`/`control-*` 这些外部技能、`agent-transcripts/` 路径。
- 和用户规则冲突最大的是 **Autonomy 段与“每个剧本最后都开 PR”**（提交、推送、worktree、外部写操作都不先确认），其次是**强制委派、多模型面板**，与 CLAUDE.md 里“只有能实质降本才用 sub-agent”的规则相冲突。这些要改写，不能照搬。
- devflow 现在的情况：6 个技能各自靠 description 自动触发，没有统一入口，没有原则词表，也没有复盘闭环。autorun 的决策日志、守卫钩子和 `install.sh` 已经是 pstack 同类机制里做得更结构化的部分。

> 标注约定：〔已确认〕是我在源码或本机配置里看到的；〔推测〕是基于对 Claude Code 能力的记忆，没有在本次会话里核对文档，验证方法写在括号里。

---

## 1. 入口路由（poteto-mode）

### 1.1 剧本匹配与 todo 抄写

- **问题**：一个 agent 面对任意任务时，容易自选流程、漏步骤，用户也看不到它打算做什么、跳过了什么。
- **pstack 解法**
  - 入口技能 frontmatter 带 `disable-model-invocation: true`，只在用户输入 `/poteto-mode` 时加载（skills/poteto-mode/SKILL.md:4）。整个插件里只有 `setup-pstack` 能由模型自己触发，其余全部要显式调用（`grep -L` 已确认；poteto-help/SKILL.md:41 也说 “Only `/setup-pstack` loads from the user's words”）。
  - 路由表就是 SKILL.md 里的一行一个剧本，每行写明适用条件（SKILL.md:125-147）。文件名规则是标题转 kebab-case（SKILL.md:121）。
  - 先开一个 todo list，前几项是剧本步骤的**原文**；决定不做的步骤也留在列表里，标 `skip: <reason>`（SKILL.md:121；guide 01-setup.md:58）。
  - 兜底规则：大型或跨切面的工作、用户离开后要信任结果的工作，路由到 `figure-it-out`；没有剧本匹配时也走它；多天、项目级的工作走 Orchestrate（SKILL.md:123）。
  - 每个剧本都以 “Run **Opening a PR**” 结尾（SKILL.md:147；opening-a-pr.md:3）。
- **机制类型**：提示词（路由表）+ 宿主的 todo 工具（让步骤可见、可审计）。没有脚本强制。Cursor 依赖只有 todo 工具和 `/` 菜单。
- **Claude Code 映射**
  - 入口做成 `~/.claude/skills/<name>-mode/SKILL.md`，加 `disable-model-invocation: true`〔已确认：Claude Code 技能支持该字段，本机 devflow-autorun 已在用〕。
  - 剧本放在 `playbooks/*.md`，按需 Read，只把路由表留在 SKILL.md 正文里。
  - todo 用 Claude Code 自带的 TodoWrite/任务工具，规则照写：“步骤原文抄入，跳过的写 `skip: 原因`”。
- **成本**：每次调用多读 SKILL.md（147 行）和一个剧本（10 到 150 行）。todo 抄写几乎不花 token，收益是用户能看到流程。
- **devflow 对应物与差距**：没有对应物。devflow 6 个技能都没有 `disable-model-invocation`，靠 description 关键词自动触发（例如 devflow-plan 的 description 列了“我有个想法/想做/方案/设计/计划”）。差距有三点：一是没有统一入口，任务在 plan、debug、impl 的边界上触发不稳；二是没有“步骤原文入 todo + skip 原因”这种可见性；三是 plan→impl→verify→commit 的衔接靠用户手动发起，也就是用户说的“偏手动”。
- **判断**：**改写**。单一入口、路由表、步骤入 todo、显式 skip 都照搬。“每个剧本以开 PR 结尾”要删，改成“以收尾报告结尾，提交和推送由用户确认”。

### 1.2 Custom Mode（常驻）

- **问题**：用 Enter 附加的技能只对一条消息生效，后续追问会逐渐脱离这个模式（poteto-help/SKILL.md:53）。
- **pstack 解法**：用 Option/Alt+Enter 把技能变成 Cursor 的 Custom Mode，此后每轮都在上下文里，闲聊时不介入，直到用户退出（README.md:93；poteto-help/SKILL.md:54-55；01-setup.md:60）。
- **机制类型**：完全依赖 Cursor（Custom Mode 只在 Agents Window 和 CLI 里有）。
- **Claude Code 映射**〔都是推测，需要逐项核对官方文档〕：
  1. **CLAUDE.md 常驻一段很短的指针**，例如“非琐碎任务先读 `~/.claude/skills/x-mode/SKILL.md` 并按剧本走”。这是成本最低、最可靠的常驻方式，但每轮都会占一点上下文，而且会对所有任务生效，相当于“永远开着 Custom Mode”。
  2. **Output style**（`~/.claude/output-styles/*.md`，用 `/output-style` 切换）。它最像 Custom Mode：可切换，切换后持续生效。风险是 output style 会替换系统提示词里的一部分，需要确认 `keep-coding-instructions` 一类字段是否存在、默认值是什么。另外 output style 本来是管“说话方式”的，把路由塞进去属于借用。（验证：问 claude-code-guide，或读官方 output-styles 文档。）
  3. **UserPromptSubmit 钩子 + 开关文件**：`/x-mode on` 写一个标记文件，钩子每轮注入一行提醒。可以开关，也可以按项目区分，但多了一个脚本要维护。本机 settings.json 已经注册了 UserPromptSubmit 钩子〔已确认存在该事件键〕，有现成的基础。
  4. 去掉 `disable-model-invocation`，让入口靠 description 自动触发。这就回到 devflow 现在的问题，不推荐。
- **成本**：方案 1 每轮多几十个 token；方案 2、3 只在开启时付费。
- **devflow 对应物**：无。CLAUDE.md 目前只放用户规则。
- **判断**：**改写**。推荐“显式 `/x-mode` + CLAUDE.md 里一句短指针”，output style 作为可选实验。

### 1.3 “new task” 与短跟进

- **问题**：长对话里切换话题时，模式会把新问题当成上一个剧本的下一步；反过来，上下文已经足够时，用户不该被迫写长提示。
- **pstack 解法**：说 “new task” 就重新匹配剧本（02-poteto-mode.md:87-95；poteto-help/SKILL.md:57,134；prompting.md:36）。“do it / continue / keep going until done” 本身就是完整提示，因为结构在剧本里（02-poteto-mode.md:69-85；prompting.md:33-35）。
- **机制类型**：纯约定，靠 agent 识别这个短语，没有结构保证。
- **Claude Code 映射**：入口 SKILL.md 写明“用户说‘新任务’或 `new task` 时重新匹配剧本、新开 todo”。在 Claude Code 里，`/clear` 往往比 “new task” 更干净，因为它连旧上下文一起丢掉。可以在入口里说明两者的取舍：前者保留上下文，后者省 token、不受旧任务污染。
- **成本**：几乎为零。
- **devflow 对应物**：无。
- **判断**：**照搬**，中文关键词用“新任务”。

### 1.4 帮助入口（poteto-help）与 in-your-own-words、bro

- **问题**：技能多了以后，用户不知道该用哪个；还有 agent 误解用户目标、回复满是术语这两类问题。
- **pstack 解法**
  - `/poteto-help` 只回答问题、给一段可直接发送的提示，**不开工**，因为一次 pstack 运行花的 token 是真金白银（poteto-help/SKILL.md:9）。它有“症状 → 修复”表（:129-140）和“近似技能怎么区分”（:97-104）。
  - `/in-your-own-words` 只有一句：复述用户的目标和问题（in-your-own-words/SKILL.md:7）。
  - `/bro` 只有一句：用人话重说上一条回复（bro/SKILL.md:7）。
- **机制类型**：提示词，与 Cursor 无关。
- **Claude Code 映射**：直接可用。help 的内容可以并入入口技能的 README 或 references，不必单独做一个技能。
- **devflow 对应物**：devflow-plan 第 1 阶段要求先复述需求（devflow-plan/SKILL.md:19-34），AGENTS.md:3 要求“先读懂用户已给的材料”，这两处覆盖了 in-your-own-words 的作用。help 和 bro 没有对应物。
- **判断**：help **不需要**（只有一个用户，技能数量少，入口的路由表本身就是帮助）；in-your-own-words **不需要**，已经被 plan 覆盖；bro **照搬**，做成一行中文技能，例如 `/说人话`，成本几乎为零。

### 1.5 委派包装 agent（poteto-agent）

- **问题**：subagent 不知道主会话正在用的风格和原则，委派出去的工作会偏离。
- **pstack 解法**：`poteto-agent` 是一个包装 agent，开工前必须完整读一遍 poteto-mode 的 SKILL.md；找不到就停下来告诉父 agent（agents/poteto-agent.md:3,9）。主会话自己跑剧本，不能把剧本本身交给 poteto-agent（SKILL.md:93）。
- **机制类型**：agent 定义加提示词。找文件的逻辑依赖 Cursor 的路径（`~/.cursor/plugins/`）。
- **Claude Code 映射**：`~/.claude/agents/*.md` 的 frontmatter 支持 `model`、`effort`、`tools`〔已确认：本机 explorer/researcher/worker 就是这么写的〕。是否支持用 `skills:` 字段预加载技能是〔推测〕（验证：查 subagents 文档）。不支持的话，就在 agent 正文里写死 SKILL.md 的绝对路径。
- **devflow 对应物**：用户已有 explorer、researcher、worker 三个 agent（model opus，effort medium），worker 的提示里有“不扩大范围、如实报告验证结果”。devflow-impl/references/delegation.md 有一个 worker prompt 模板。
- **判断**：**改写**。在现有的 worker/explorer 里加一句“先读 `<入口>/principles/index.md`”，不新建 poteto-agent。

---

## 2. 原则体系（24 条 principle-*）

### 2.1 引用与“转向”机制

- **问题**：一长段纠正指令既贵又不精确；agent 嘴上说“我遵循了原则 X”，实际上没有改变任何决策。
- **pstack 解法**
  - 24 个单原则技能，全部 `disable-model-invocation: true`，平时不占上下文（例如 principle-attack-the-premise/SKILL.md:4）。
  - 入口 SKILL.md 内联一份索引，每条写“何时适用 + 一句规则”（SKILL.md:38-79）。要应用某条原则时，必须读完对应的 leaf 文件（SKILL.md:40）。
  - 回复里必须写明“哪条原则改变了哪个决定”，而且只能引用本会话读过的原则（SKILL.md:15）。原则名后面没有对应的决定，就说明是在堆名词（08-principles.md:27）。
  - 用户转向时只说名字，例如 “apply prove it works. show me the real output”（08-principles.md:15-25；prompting.md:49-51）。这能生效，是因为 agent 已经读过索引（prompting.md:51）。
  - 原则之间互相链接，并写明“与 X 的区别”，例如 build-the-lever:23、attack-the-premise:23、explain-the-number:17。
  - 部分原则自带“你跳过了它”的检测标志，例如 build-the-lever:18 “如果你引用了它而 diff 里没有脚本，就是没应用”；model-the-domain:24；explain-the-number:15；test-behavior:9。
- **机制类型**：提示词。索引常驻（随入口加载），细节按需 Read。与 Cursor 无关。
- **Claude Code 映射**：不要做成 24 个 slash 技能，会把 `/` 菜单塞满。改成入口技能下的 `principles/index.md`（一行一条）加 `principles/<name>.md`。“名字转向”依赖索引已经在上下文里：入口被调用时它自然在；如果想在入口之外也能用名字转向，就把索引放进 CLAUDE.md（大约 30 行，每轮都占上下文，需要权衡）。
- **成本**：索引大约 40 行；每条 leaf 10 到 34 行，按需读。“回复里必须点名原则”会让每次回复都变长，对一个单人用户来说收益很低。
- **devflow 对应物**：没有显式的原则词表，类似的规则散落在各个技能里。例如 devflow-debug:8 “只修问题本身，不加防御代码”对应 fix-root-causes 和 laziness；devflow-verify:15-21 的三条不变量对应 prove-it-works；devflow-impl:13 “不新增计划未要求的持久状态和公共契约”对应 subtract-before-you-add；devflow-autorun 的 check.sh/guard.sh 对应 encode-lessons-in-structure。
- **判断**：**改写**。保留“索引 + leaf + 用名字转向 + 跳过检测标志”的结构。删掉“每次回复必须点名原则”，改成“只在原则改变了决定时写一句”。

### 2.2 对 Claude Code 和这位用户的价值分档

| 档位 | 原则 | 理由 |
|---|---|---|
| 高价值，照搬 | prove-it-works, fix-root-causes, test-behavior-not-implementation, explain-the-number, attack-the-premise, encode-lessons-in-structure, sequence-verifiable-units | 规则具体，自带“你跳过了它”的检测标志，与 devflow-verify、devflow-debug 的现有要求一致，而且更锋利。test-behavior:11-19 那份“会假通过的断言清单”尤其值得直接用。 |
| 有价值，并成少数几条 | laziness-protocol + subtract-before-you-add；model-the-domain + foundational-thinking + type-system-discipline + boundary-discipline；migrate-callers + outcome-oriented-execution；make-operations-idempotent + separate-before-serializing-shared-state；minimize-reader-load | 内容彼此重叠，例如 foundational-thinking:21 和 subtract:13 都在说“先删再建”。合并成 4 到 5 条，名字更容易记，适合用来转向。 |
| 需要改写才能用 | build-the-lever | 默认“非琐碎工作就写脚本”（:12），对单人小改动成本过高。改成“同一操作第二次手做，或结果需要可复跑证明时”才适用。 |
| 需要改写才能用 | guard-the-context-window | “大块内容交给 subagent”（SKILL.md:74）与 CLAUDE.md:5 冲突。Claude Code 有自动压缩，而且 Read 支持 offset/limit。改成“先用定位工具缩小范围，只有满足 CLAUDE.md:5 的条件才委派”。 |
| 不需要 | never-block-on-the-human | 与 AGENTS.md:5 正面冲突（见第 6 节）。可取的部分（可逆的小决定先做再报）已经由 AGENTS.md:4 的“直接推荐并说明代价”覆盖。 |
| 不需要或降级 | exhaust-the-design-space, experience-first, redesign-from-first-principles | 第一条要求每次都做 2 到 3 个原型，成本高，devflow-plan 第 2 阶段已经要求比较可信方向。后两条偏口号，缺少检测标志（exhaust 的正文只有 1 行，:9）。可以作为 plan 里的一句话提示。 |

---

## 3. 复盘与定制

### 3.1 /correct：把重复纠正变成仓库结构

- **问题**：用户在聊天里反复纠正同一类错误，每次纠正只对一次运行有效。
- **pstack 解法**：从提交、revert、review 评论、agent 指令文件、解释 workaround 的注释里归纳**错误类**，同一类出现两次才算数（correct/SKILL.md:15）。按层级修复，能在高层解决就不往低层放：架构 → 类型/lint/CI（报错信息里要写明正确用法）→ 测试 → 文档，文档放在最后，因为跳过文档时什么都不会报错（:17-22）。每个新检查都要证明它能在一个真实的历史错误上失败（:26）。在 agent 指令文件里维护一张“规则 ↔ 由什么强制”的表，有规则但没有强制手段的错误再次出现时，就按重复处理（:28-30）。
- **机制类型**：提示词驱动，产出是结构（lint、类型、测试、钩子）。与 Cursor 无关。
- **Claude Code 映射**：数据源是 `git log`、revert、`~/.claude/projects/<项目>/*.jsonl` 会话记录〔推测路径格式，本机已确认存在 `~/.claude/projects/` 目录〕。“规则表”放在项目的 CLAUDE.md。Claude Code 还多了一层 pstack 没有列出的手段：**PreToolUse/Stop 钩子**。用户已经用 PreToolUse 钩子给 autorun 做守卫，这正好可以作为“lint 之上、文档之前”的一层。
- **成本**：一次挖掘加上若干个修复提交。挖掘会话记录的 token 开销不小，要限定时间窗。
- **devflow 对应物**：没有对应技能。但 devflow 本身就是这个思路的产物：autorun 的守卫、check.sh、`test.sh`，以及 README.md:40-41 的注意事项，都是“把教训写进结构”。差距在于缺少一个反复运行、能发现新错误类的入口，也缺少规则表。
- **判断**：**改写后照搬核心**。层级顺序、“两次才算一类”、“证明检查会在真实历史错误上失败”、规则表都保留。“每类一个提交”改成“产出补丁和提交计划，提交前确认”（AGENTS.md:5）。

### 3.2 /reflect：从一次会话提炼技能修改

- **问题**：一次长任务里学到的东西会随会话结束丢失；但凭单次会话直接改技能，又容易过拟合。
- **pstack 解法**：定位当前会话的记录，严禁跨工作区 glob（reflect/SKILL.md:15）。并行启动 3 个评审（判断、工具、发散），再由 1 个综合者输出 Accepted/Rejected/Backlog（:23-39）。能用 lint 或脚本强制的条目移到 Backlog（:41-43）。Accepted 要等用户逐行批准才应用（:47）。综合者的筛选标准是精华：持久性、具体性、优先改已有技能、多个评审一致、能改变决定、能用结构就不用文字、技能确实被用到了、不和已有内容重复，外加“丢掉会漂移的实现细节”的正反例（synthesizer.md:15-34）。它还把评审输出当作不可信数据，防提示注入（synthesizer.md:3）。
- **机制类型**：多 subagent 加多模型（判断用 Opus，工具用 Grok）。依赖 Cursor 的会话记录路径和 `create-skill`。
- **Claude Code 映射**：会话记录在 `~/.claude/projects/<编码后的cwd>/<session-id>.jsonl`〔推测，可用 `ls -t` 核对〕。4 个 subagent 不满足 CLAUDE.md:5 的“实质降本”条件。单人场景下，建议由主 agent 直接按 synthesizer 的标准做一遍；只有会话特别长时，才派一个 explorer 去读记录、做摘要。技能修改用 `anthropic-skills:skill-creator`〔本机技能列表中已确认存在〕。
- **成本**：原版 4 个 xhigh 级 subagent；改写后大约是一次主会话阅读的成本。
- **devflow 对应物**：无。devflow-report 是 Git 周报，回答“做了什么”，不回答“学到什么”。
- **判断**：**改写**。保留 synthesizer 的标准和“逐行批准”，去掉三评审面板。“Backlog 不等批准直接提交到跟踪系统”（:49）要删掉，这是外部写操作。

### 3.3 /ketchup：回来后的追赶摘要

- **问题**：用户离开一段时间，回来后要读一长串输出才知道发生了什么。
- **pstack 解法**：只读，150 词以内；第一句说有几件事需要用户；用“行动项 + 推荐 + 不回答会怎样”的格式；用图示，并严格限制每个图示的字数（ketchup/SKILL.md:15-37）。
- **机制类型**：提示词。依赖 Cursor 的 `/visualize` 和 Mermaid 渲染。
- **Claude Code 映射**：终端不渲染 Mermaid，图示部分要去掉。文本部分（数需要用户处理的事项、行动项写清默认后果、不写哈希和路径）可以直接用。
- **devflow 对应物**：`/devflow-autorun 进展`，只读，汇报运行到了哪一步（devflow-autorun/SKILL.md:72）。范围只覆盖 autorun。
- **判断**：**不需要单独技能**。把“第一句说几件事待你处理，每个行动项写推荐和默认后果”这条写进入口的“回复规范”即可。

### 3.4 /automate-me：从历史生成个人 mode 技能

- **问题**：poteto-mode 是别人的风格，用户需要自己的版本。
- **pstack 解法**：先检查是否已有 `-mode` 技能，有就进入更新模式，只挖掘上次修改之后的历史（automate-me/SKILL.md:17-25）。把历史分成 3 段并行挖掘，在 2 段以上出现的信号才算高置信（:31-40）。再用多选题问用户，最多一两轮（:44-48）。产出默认 `disable-model-invocation: true`（:73）。最后在 worktree 里提交并开 PR（:83）。护栏：不过拟合、引用而不内联、没有特殊规则的章节不写（:87-92）。
- **机制类型**：多 subagent 挖掘，加 Cursor 的 `AskQuestion` 和 `create-skill`。
- **Claude Code 映射**：数据源是 `~/.claude/history.jsonl` 和 `~/.claude/projects/*/`〔已确认目录存在〕，以及 `~/.codex/` 下的历史〔推测〕。多选提问在 Claude Code 里有对应工具〔推测：AskUserQuestion〕。产出直接写进 devflow 仓库，不走 worktree 和 PR。
- **成本**：一次性的，3 个 subagent。这次用户本来就要“重建体系”，所以值得做一次。
- **devflow 对应物**：无。现在的 devflow 是手写的。
- **判断**：**改写，并作为重建的第一步运行一次**。用它从真实历史里挖出新入口应包含的规则，而不是凭印象写。“跨工作区 glob 禁止”在这里要反过来处理：单人全局技能需要跨项目挖掘，但必须由用户明确授权范围。

### 3.5 authoring-a-skill 剧本

- **问题**：手写的 SKILL.md 质量参差，描述写不准就触发不了，链接和引用会坏。
- **pstack 解法**：用 `create-skill`；校验 frontmatter 有 name 和 description、引用的文件存在、跨技能链接能解析；结构性的改动要有测试用例（authoring-a-skill.md:5-8）。写作原则：拿不准就删；只留能改变决定的句子；直接说做什么，不讲理由；用路径委托给其他技能，不复述（:10）。还有一条：技能坏了就单独提 PR 修，不要混进功能工作（SKILL.md:35；09-make-it-yours.md:98）。
- **机制类型**：提示词加 Cursor 内置技能。
- **Claude Code 映射**：用 `skill-creator` 和 `claude plugin eval`/`/skill-doctor`〔本机 agent 列表的描述里提到了这两个，具体能力是推测〕。校验那一步建议写成脚本，并入 devflow 的 `test.sh`：检查 frontmatter、相对链接、`playbooks/` 里的文件是否存在。
- **成本**：低。
- **devflow 对应物**：`test.sh` 只测 autorun 的脚本，不校验技能文件。
- **判断**：**改写**。校验写成脚本（这本身就是 encode-lessons-in-structure）；“技能坏了单独修”照搬，但改成“单独提交，并先确认”。

### 3.6 eval 剧本：盲测技能修改

- **问题**：基于一次糟糕会话写的技能修改容易过拟合，多次修改之后技能会漂移。agent 知道自己在被评估时，行为会改变。
- **pstack 解法**：候选 agent 看不到 eval、test、judge 之类的词；环境做脱敏；不告诉候选其他候选的存在；裁判只看匿名标签；判断它有没有按链路走，看会话记录里它实际打开了哪些文件，而不是看它自己怎么说；最后主 agent 亲自读一遍所有输出（eval.md:5-23）。
- **机制类型**：多模型 subagent 加会话记录。依赖 arena 技能和 Cursor 的记录路径。
- **Claude Code 映射**：候选用 `claude -p` 在脱敏的临时目录里跑〔推测〕。难点在于，候选会加载用户全局的 `~/.claude/CLAUDE.md` 和技能，变量隔离要靠 `--settings`/环境变量或单独的配置目录〔推测，需验证〕。`claude plugin eval` 可能是更现成的框架〔推测〕。Claude Code 里没有不同的模型家族，“不同家族的裁判”可以用 Codex CLI 代替〔推测〕。
- **成本**：高，N 个候选加 1 个裁判。
- **devflow 对应物**：无。
- **判断**：**暂不需要**，留作以后的选项。单人使用、技能数量少的情况下，“读几次真实会话 + 用户的直接感受”就够了。只有准备大改入口路由时才值得做一次。可以先把盲测的原则（不在提示里泄露评估目的、根据实际读过的文件判断）记下来。

---

## 4. 安装与模型配置

### 4.1 安装

- **pstack 解法**：Cursor 插件，`/add-plugin pstack` 安装（README.md:17-19）。`.cursor-plugin/plugin.json` 声明 `skills` 和 `agents` 目录（:29-30）；根目录的 `plugin.json` 是 agent-plugins.org 的通用 schema。安装后在用户调用技能之前什么都不会发生（poteto-help/SKILL.md:41）。
- **机制类型**：Cursor 插件市场。
- **Claude Code 映射**：Claude Code 也有插件格式（`.claude-plugin/plugin.json` 加 marketplace）〔推测，需要核对字段〕。但插件里的技能会带命名空间（`plugin:skill`），而且 Codex 不认这种格式。
- **devflow 对应物**：`install.sh` 用符号链接把技能装到 `~/.agents/skills` 和 `~/.claude/skills`，devflow-report 只装到 Codex。它是幂等的，不覆盖已有内容，还会检查钩子但不修改 settings（install.sh:10-48）。
- **判断**：**不需要改成插件**。保留 `install.sh`：它同时覆盖 Codex 和 Claude Code，不改 settings 的做法也比插件更符合用户的规则。新体系只需要扩充链接目标，再加一个技能文件校验。

### 4.2 setup-pstack 与 pstack-models.mdc

- **问题**：不同角色（写代码、判断、评审面板）用不同模型和推理预算，用户想控制成本。
- **pstack 解法**：探测可用的模型 slug，选择 4 档预算，在 slug 上调整 effort 档位，然后写入 `~/.cursor/rules/pstack-models.mdc`（`alwaysApply: true`，每个角色一行，`inherit-parent`/`auto` 表示沿用父会话模型）（setup-pstack/SKILL.md:8-66）。所有技能读这个规则，缺失时用默认值（README.md:261）。默认分工：写代码交给 Grok，最难的任务、文字和判断交给 Opus（SKILL.md:95）。还有一个按难度分档的规则：最难的改动交给最强的判断模型，琐碎的机械修改交给快速模型（SKILL.md:95）。
- **机制类型**：Cursor 的 always-apply 规则加 Task 工具的 `model` 参数。完全依赖 Cursor：多家族 slug 和 effort 编码在 slug 里。
- **Claude Code 映射**：Agent 工具的 `model` 参数只有 sonnet/opus/haiku/fable 这几个别名〔本会话工具定义已确认〕，effort 不能按次传，只能写在 agent 定义的 frontmatter 里〔已确认：本机 agent 文件有 `effort: medium`〕。所以“按角色配置模型”在 Claude Code 上的自然形态，就是 **`~/.claude/agents/` 下的几个 agent 文件**，每个文件写死 model 和 effort。用户已经这样做了：explorer、researcher、worker 都是 opus/medium。不需要配置技能，也不需要规则文件。
- **成本**：零，已经存在。
- **devflow 对应物**：上面三个 agent 文件，加上 CLAUDE.md:5-7。
- **判断**：**不需要**。不做 setup 技能。如果以后想加“只读快速档”，就新增一个 `model: haiku` 或 `sonnet` 的 agent 文件。

### 4.3 与 CLAUDE.md 子 agent 规则的冲突

| pstack 规则 | 位置 | 与 CLAUDE.md 的关系 |
|---|---|---|
| Feature 剧本第 4 步**强制**委派写代码，“没有带理由跳过的出口，Laziness Protocol 也不能推翻” | feature.md:12 | 与 CLAUDE.md:5 正面冲突。用户规则是默认主 agent 自己做。 |
| Bug fix 剧本“把调查和修复都委派给 subagent” | bug-fix.md:3 | 冲突。 |
| 每次 Task 默认 `run_in_background: true`，每个角色显式指定模型 | SKILL.md:95 | 后台运行不冲突；显式指定模型时只要不选 Fable 就不冲突。 |
| 最难的改动交给最强的判断模型 | SKILL.md:95 | 在 Claude Code 上，“最强”就是 Fable，而 CLAUDE.md:7 规定 Fable 只用于“重大架构方案的起草或设计”，所以冲突。应改成“最难的实现用 Opus 加更高 effort 的 agent 文件”。 |
| how、why、architect、interrogate、arena、reflect 默认双模型或多评审面板 | setup-pstack:61-65；reflect:29-33 | 冲突：面板的收益是“不同家族的视角”，但 Claude Code 里只有一个家族，降本更谈不上。 |
| “你对每个 subagent 的产出负责，审阅 diff，自己写总结，不转述” | SKILL.md:97 | **一致**，对应 CLAUDE.md:6。 |
| 默认用全新的 subagent，把范围整合后交给它 | SKILL.md:99 | 不冲突，可以照搬到 delegation.md。 |

结论：委派相关的要求要整体降级为“允许，但只在满足 CLAUDE.md:5 时使用”。devflow-impl/references/delegation.md:3-5 已经是这个立场，比 pstack 更符合用户规则，应当保留。

---

## 5. 写作规范与“简体中文、结论先行”

- **问题**：AI 腔、空话、虚构引用、把猜测写成事实。
- **pstack 解法**
  - Writing the reply（SKILL.md:101-113）：短的陈述句；完全不用长破折号；句中不用冒号作连接；简洁不等于丢内容；先说对使用者和维护者的影响；不编造链接；每个论断在同一句里带证据或标签（实测、推断、猜测）；能自己跑的检查不要交给人。
  - unslop：33 条规则，编号稳定，其他技能可以按编号引用（unslop/SKILL.md:13）。几乎全部针对英文：AI 词汇表、title case、弯引号、over-compression 等（:17-62）。
- **机制类型**：提示词。
- **与用户规则的协调**
  - 用户全局规则里的写作要求只有“始终用简体中文回复”（AGENTS.md:1）和“推测要标明，并说明如何验证”（AGENTS.md:3）。“结论先行”在 devflow 的技能模板里，不在全局规则里（devflow-debug:17、devflow-impl:30）。
  - **一致的地方**：每个论断带证据或标签，对应 AGENTS.md:3 的“标明推测”和 devflow-research:15 的 `[推测]`；不编造链接；简洁但不丢内容；能自己跑的检查不交给用户。
  - **冲突或不适用的地方**
    1. “不用长破折号”和“句中不用冒号”：devflow 模板本身就是 `**结论**：<…> — <…>`（devflow-debug:20），中文全角冒号也是常规标点。照搬会和现有模板打架。
    2. unslop 的词表和 title case 等规则对中文无效。中文需要自己的一份“AI 腔”清单，例如“值得注意的是”“总的来说”“赋能”“抓手”“闭环”滥用、加粗泛滥、每段都用三点式。
    3. “先说对使用者和维护者的影响”和“结论先行”可以兼容：第一行写结论，第二行写影响。
    4. “点名影响决策的原则”会拉长回复，与结论先行相悖。改成可选。
- **Claude Code 映射**：通用的写作规则放在 CLAUDE.md（全局，所有回复都适用），不放在入口技能里。中文去 AI 腔的清单作为 `references/writing-zh.md`，在生成文档或 PR 描述时读取。
- **devflow 对应物**：各技能的回复模板（结论加证据加验证），以及 devflow-research 的 `[推测]`、`实际演练/推演` 标签。在“证据标签”这一点上，devflow 比 pstack 更细。
- **判断**：**改写**。证据标签、不编造、不把检查交给用户、简洁不丢内容这几条照搬；标点规则和英文词表不要；新写一份 15 条左右的中文版 unslop。

---

## 6. Autonomy 与 AGENTS.md 的冲突点（逐条）

| # | pstack 条目（文件:行） | 内容 | 冲突的用户规则 | 建议 |
|---|---|---|---|---|
| 1 | poteto-mode/SKILL.md:83 | “Just do it”：任何 MCP 工具、外部操作（团队聊天、工单更新、启动 eval）都不问 | AGENTS.md:5 外部发布前先确认 | 只读的 MCP 调用可以直接做；任何写到外部系统的操作都要确认。 |
| 2 | SKILL.md:85；never-block-on-the-human:13 | 只有不可逆操作才暂停（force-push、部署、删数据、给客户发消息） | AGENTS.md:5 把提交、推送也列入需确认 | 改成用户的清单：提交、推送、外部发布、丢数据、不可逆操作都需要确认。 |
| 3 | SKILL.md:147；opening-a-pr.md:3,7,30 | 每个剧本最后都开 PR；大量提交；可以 amend；PR 直接设为 ready | AGENTS.md:5；devflow-commit:17 禁止 amend 和 push | 剧本以收尾报告结尾；提交走 devflow-commit，并且要用户明确要求；去掉 PR。 |
| 4 | opening-a-pr.md:5 | 在 main 分出的 worktree 里工作；多个 Task 各开一个 worktree；`git reset --hard origin/<branch>`；“worktree 乱了就从 main 重置” | AGENTS.md:6 未经要求不建 worktree；AGENTS.md:5 丢弃改动前要列清单并确认 | 删除。默认在当前目录工作；需要隔离时先询问。 |
| 5 | SKILL.md:87 | 用户说一句 “going to bed / don't stop” 就切到全自主 | 与 AGENTS.md 不直接冲突，但 devflow-autorun 要求有书面契约和明确武装（devflow-autorun/SKILL.md:10） | 保留 devflow 的做法：口头一句话不等于授权，无人值守必须走 autorun 的武装流程。 |
| 6 | SKILL.md:35 | 任务中遇到坏掉的技能，单独提 PR 修，不阻塞 | AGENTS.md:4 目标由用户设定；AGENTS.md:5 提交前确认 | 改成：记下来，收尾时报告，修改前确认。 |
| 7 | autonomous-run.md:9 | 运行中发现的问题都由 agent 自己处理（坏技能、相关 bug、不稳定的验证器），各自单独开 PR，不留给人 | AGENTS.md:4 目标由用户设定，不能自行扩大范围；autorun 只能在写范围内改，越界就停放 | 删除。按 devflow-autorun-tick:39-40 停放并记录。 |
| 8 | reflect/SKILL.md:49 | Backlog 条目不等批准，直接提交到团队跟踪系统 | AGENTS.md:5 外部发布 | 删除。只列在报告里。 |
| 9 | automate-me/SKILL.md:83 | 开 worktree、提交、开 PR | AGENTS.md:5、6 | 直接写入 devflow 仓库的工作区，提交前确认。 |
| 10 | correct/SKILL.md:26 | “现在就修最常见的几类，每类一个提交” | AGENTS.md:5 | 先产出补丁，确认后再提交。 |
| 11 | worktree-cleanup.md:6-7 | 干净、已合并、没在用的 worktree 直接删；未跟踪的临时文件“可以丢，但要列出文件名”；`rm -rf` 构建产物 | AGENTS.md:5 删除未跟踪文件前要列清单**并等待确认** | 所有删除都先列清单，等待确认。 |
| 12 | SKILL.md:20 | 在全自主授权下，只有运营者能做的决定也先套用默认值再报告 | AGENTS.md:4 偏离原要求时由用户决定 | 只在 autorun 契约明确覆盖的范围内适用；否则停放。 |
| 13 | feature.md:12；bug-fix.md:3 | 强制委派 | CLAUDE.md:5（不是 AGENTS.md，但属于同类授权问题） | 见 4.3。 |
| 一致 | SKILL.md:89 “No 是可以接受的回答”；SKILL.md:111 “能自己跑的检查不交给人”；worktree-cleanup.md:6 “未提交的工作要先展示 diff 并等待决定” | 坦率反对、自己验证、保护未提交的工作 | 与 AGENTS.md:4、AGENTS.md:5 一致 | 照搬。 |

---

## 本组总结

**最值得采用的 3 点**

1. **单一显式入口，剧本步骤原文写入 todo，跳过的步骤写明原因**（SKILL.md:121）。这直接解决 devflow“多个技能各自靠 description 触发、衔接靠手动”的问题，而且每一步都可审计。
2. **原则词表：索引常驻，细节按需读，用名字转向，每条带“你跳过了它”的检测标志**（SKILL.md:38-79；08-principles.md）。用户用一句话纠偏，agent 也很难只挂个名字不落实。保留 8 到 10 条，不要 24 条。
3. **把纠正变成结构的闭环**：`/correct` 的层级顺序、“两次才算一类”、“证明检查会在真实历史错误上失败”、规则表，加上 `/reflect` 综合者的筛选标准（correct/SKILL.md:15-30；synthesizer.md:15-34）。Claude Code 的钩子是 pstack 没有的强制层，用户也已经在用。

**最不值得采用的 3 点**

1. **Autonomy 段和“每个剧本都以开 PR 结尾”**：与 AGENTS.md:5、6 有十多处冲突（见第 6 节），而且 PR 流程对个人仓库来说本身就多余。
2. **多模型评审面板和强制委派**（setup-pstack、reflect 的 3+1、Feature 强制委派）：Claude Code 只有一个模型家族，面板失去意义，又违反 CLAUDE.md:5。
3. **setup-pstack、模型配置规则、Custom Mode、poteto-help、ketchup 的图示、英文 unslop 词表**：要么完全依赖 Cursor，要么已经有更好的本地等价物（agent 文件、install.sh、中文写作规则）。

**新体系的入口应该长什么样**

一个显式调用的入口技能，例如 `/dev`，`disable-model-invocation: true`。它的 SKILL.md 只放三样东西：一张路由表，每行写“触发条件 → `playbooks/<名>.md`”；一份大约 10 条的原则索引，每行写“何时适用 + 一句规则 + `principles/<名>.md`”；一段授权边界，原样引用 AGENTS.md:5、6 的确认清单，再加上“无人值守只能走 autorun 武装”。被调用时，它先复述目标和完成判据，然后匹配剧本，把剧本步骤原文写入 todo，跳过的步骤写 `skip: 原因`。用户说“新任务”就重新匹配。剧本以中文收尾报告结尾，格式是结论、证据、未验证项、待你确认的提交或推送。现有的 devflow-plan、research、debug、impl、verify、commit 降为剧本或被剧本引用的子技能，并去掉自动触发，避免和入口抢路由。CLAUDE.md 只增加一句“非琐碎任务建议用 `/dev` 开始”和通用写作规则，不放路由内容。是否用 output style 或 UserPromptSubmit 钩子做常驻，等跑通以后再试，这部分是推测，需要先核对文档。第一步先跑一次改写过的 automate-me，从 `~/.claude/projects` 和 `history.jsonl` 里挖出用户真实反复出现的偏好，用来填写路由表和原则，不要凭印象写。
