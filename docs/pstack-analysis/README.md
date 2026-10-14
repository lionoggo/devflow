# pstack 源码分析与新体系方向

> 日期 2026-10-14。pstack 版本：cursor/plugins `837067b`（pstack v0.15.23，161 个文件，53 个技能）。
> 起因：用户认为 devflow 本质偏手动，希望参考 pstack 针对各场景的解法重建一套。
> 本文是汇总；四份分组报告在同目录，每个子场景都有 pstack 出处（文件:行号）、机制、Claude Code 映射、成本、devflow 差距和判断：
> 1. `1-understand-design.md`：理解代码、设计（14 个子场景）
> 2. `2-build-verify-ship.md`：构建、清理、验证、发布（19 个子场景，含 11 处规则冲突）
> 3. `3-long-running.md`：长任务与无人值守（10 个子场景，含对 `docs/plan-unattended.md` 的 14 条修改建议）
> 4. `4-router-retro-setup.md`：入口路由、原则、复盘与定制、安装配置（含 13 处规则冲突）
>
> 报告由四个子 agent 并行阅读源码写成，主 agent 抽查了关键引用：除 setup-pstack 外全部技能都是 `disable-model-invocation: true`；Orchestrate 的 gates 带默认值、绕开继续做（`orchestrate.md:30,105-107`）；Feature 强制委派（`feature.md` "Mandatory: no skip-with-reason"）；`/correct` 的修正层级（`correct/SKILL.md:15-30`）。

## 1. pstack 的核心是什么

53 个技能里，真正撑起"不用手动"的是五件事：

1. **单一显式入口加剧本**：`/poteto-mode` 按路由表匹配 23 个剧本之一，把剧本步骤原文抄进 todo，跳过的步骤写 `skip: 原因`。用户只说目标和完成条件，后续"continue""do it"就够了，因为结构在剧本里。
2. **可按名字引用的原则词表**：24 条原则，入口只放索引（何时适用 + 一句话），细节按需读。用户一句"prove it works"就能把 agent 拉回正轨；每条原则自带"你跳过了它"的检测标志。
3. **验证先行**：完成条件必须能判对错；为项目生成固定的验证技能（启动、自检、操作、证据、清理），让"在真实 app 里验证"变成任何 agent 都能执行的步骤。验证是最常卡在人身上的环节，pstack 把它变成 agent 能自己完成的事。
4. **卡住不停**：瓶颈期换思路；人的问题挂起并写好默认值，先做别的；能用实验回答的不问人；"要不要继续"永远不问。
5. **把错误变成结构**：`/correct` 把反复出现的错误按"架构 → 类型/lint → 行为测试 → 文档"的顺序修，并证明新检查能在真实的历史错误上失败；`/reflect` 从会话中提炼技能修改；eval 用盲测防止技能越改越偏。

其余部分要么服务于团队规模（Autopilot、Orchestrate、Shipping、benny），要么绑定 Cursor（Custom Mode、云端子 agent、`pstack-models.mdc`、`cursor-team-kit`、Grok 跨家族面板）。

## 2. 场景对照

| 场景 | pstack | devflow 现状 | 判断 |
|---|---|---|---|
| 入口与路由 | `/poteto-mode`，路由表，步骤入 todo | 6 个技能各靠 description 自动触发，衔接靠用户 | **采用**（改写）：一个显式入口 |
| 理解代码 | how、why（五级置信，"代码不能证明自身意图"）、teach、recall | devflow-research | **采用** why 的认识论框架；recall 改用 `~/.claude/projects` 路径 |
| 设计 | architect、arena、prototype、interrogate | devflow-plan | **保留** devflow-plan 为主；**采用**"用原型回答事实性分歧"和精简版 interrogate（1 个 Claude 子 agent + 1 次 codex） |
| 改动影响面 | blast-radius | 无 | **照搬** |
| 新功能、重构、性能 | feature、refactoring、perf-issue、hillclimb | devflow-impl | **采用**剧本结构；不强制委派 |
| 修 bug | bug-fix、tdd、fix-root-causes、test-behavior | devflow-debug | **并入**：先复现、红后绿、按模式修全部实例、坏测试判据 |
| 验证 | prove-it-works、create-/maintain-verification-skill、benchmark-checklist | devflow-verify（验收体系比 pstack 系统） | **保留** devflow-verify；**照搬** create-verification-skill 和 benchmark-checklist |
| 清理 | unslop、no-comments、deslop | 无 | **改写**：中文版去 AI 腔清单；no-comments 精简采用 |
| 发布 | opening-a-pr、babysit、watch-pr、bugbot-triage、shipping | devflow-commit（比 pstack 安全），commit 之后断开 | **采用** PR 正文模板、babysit、watch-pr、分诊规则，push 和开 PR 改为先确认；**不要** shipping |
| 长任务 | autonomous-run、show-me-your-work、pause-safely、session-pickup、figure-it-out | devflow-autorun（守卫未拦过违规，卡住就收尾） | **采用**：`docs/plan-unattended.md` 加第 3 组报告的 14 条修改（多阶段、按单元判死路、接手核对、暂停、收尾时检测代替运行中拦截） |
| 大规模编排 | autopilot-full/stack、orchestrate、benny | 无 | **不要** |
| 复盘与定制 | correct、reflect、automate-me、eval、authoring-a-skill | 无 | **采用** correct + reflect 的筛选标准；第一步用改写的 automate-me 从真实历史挖规则 |
| 安装与模型 | setup-pstack、`pstack-models.mdc` | install.sh、`~/.claude/agents` | **不需要**：现有 agent 文件已覆盖模型分级 |

## 3. 与用户规则的冲突（第 2、4 组合计约 15 类）

pstack 的默认姿态是"可撤销的、对外的都直接做"（`poteto-mode/SKILL.md:83`）。与 `~/.codex/AGENTS.md`、`~/.claude/CLAUDE.md` 冲突的主要有：

- **提交**：大量自动提交、rebase、amend；而用户规则是提交前先确认，devflow-commit 禁止改写历史。
- **对外**：每个剧本以开 PR 结尾（且直接 ready），babysit 自动 push、回复评论，shipping 自动合并；而用户规则是推送、外部发布前先确认。
- **worktree**：默认从 main 拉 worktree，`git reset --hard`，worktree 清理直接删；而用户规则是不经要求不建 worktree，丢数据前列清单并确认。
- **委派与模型**：强制委派写代码，多模型面板，默认 Grok；而用户规则是子 agent 只在实质降本时用，默认 Opus 或更低。
- **写作**：英文写作规则（禁破折号、冒号）；而用户规则是始终简体中文，devflow 回复模板本身就用冒号。

结论：pstack 的**流程**可以借，**授权边界**必须换成用户的。这也决定了新体系的自动化上限，见第 5 节问题 1。

两组报告的分歧：第 4 组建议无人值守保留 autorun 的正式武装、不要"不阻塞等人"原则；第 3 组认为"卡住不停"最值得采用。用户已确认无人值守照搬 pstack（一句话授权、靠提示词约束），以用户决定为准。

## 4. 方向

| 方向 | 做法 | 代价 | 评价 |
|---|---|---|---|
| A. fork pstack 改造 | 拿全部 53 个技能，替换 Cursor 依赖，逐条改写授权 | 约四成内容用不上或冲突（编排、shipping、benny、make-bot-ui、模型配置）；改写 15 类冲突散落在几十个文件 | 改完后与上游难以同步，得到的也不是"更简单" |
| B. 按 pstack 的形状新建，内容择优 | 新入口 + 剧本 + 原则 + 复盘闭环；能照搬的 pstack 文本照搬，devflow 里报告判定更好的部分（plan、verify 的验收体系、commit 的安全规则）作为剧本引用的子技能 | 一次性重写入口和剧本；需要逐个迁移现有技能 | **推荐**：解决"偏手动"的根源（没有入口、没有衔接），又不背 pstack 的团队规模包袱 |
| C. 在 devflow 上逐步加 | 保持现有技能，分批补 pstack 的点 | 最小 | 不解决"没有统一入口、靠用户衔接"这个根本问题 |

推荐 B，新体系的大致形状：

- **一个入口** `/dev`（显式调用）：复述目标和完成条件 → 按路由表匹配剧本 → 步骤原文入 todo，跳过写原因 → 结束于中文收尾报告。说"新任务"重新匹配。
- **约 10 个剧本**：调查、修 bug、新功能、重构、性能、原型、无人值守、暂停与接手、开 PR 与跟进、复盘。
- **约 10 条原则**：prove-it-works、fix-root-causes、test-behavior、explain-the-number、attack-the-premise、encode-lessons-in-structure、sequence-verifiable-units，再加合并后的"先删再建""数据形状先行""幂等与不共享"。
- **子技能**：plan、verify、commit 沿用 devflow 的（改为被剧本引用、去掉自动触发）；新增 blast-radius、create-verification-skill、benchmark-checklist、interrogate（精简）、correct/reflect。
- **授权边界**一段：原样引用用户的确认清单；无人值守按 `docs/plan-unattended.md`（修订后）。

## 5. 动手前需要用户决定的三件事

1. **自动化边界**：本地提交是否改为"可撤销、直接做"（pstack 默认，也是"不手动"的关键）？push、开 PR、合并、对外发送是否仍然先问？
2. **成本**：默认精简（子 agent 和跨模型审查只在设计定型、发布前、无人值守收尾这几个关键点用），还是接受 pstack 那种大量并行？
3. **迁移方式**：新体系放在本仓库内逐步替换 devflow（同一套 install.sh），还是另起新仓库、跑通后再停用 devflow？

## 6. 下一步

1. 用户回答第 5 节三个问题。
2. 先跑一次改写过的 automate-me：从 `~/.claude/projects` 的历史会话里挖出用户真实反复出现的任务类型和纠正，用来定路由表和原则，不凭印象写。
3. 用 devflow-plan 写新体系的方案（入口、剧本清单、原则清单、授权边界、迁移步骤、验收），审查后再实施。`docs/plan-unattended.md` 作为其中"无人值守"剧本的底稿，按第 3 组报告修订。
