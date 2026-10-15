# dflow 与 pstack 能力对比

基于 dflow `1467f69`（`skills/dflow`、`skills/dflow-report`）和 pstack `837067b`（Cursor 插件）。
对比由 codex 逐个读两边的剧本、参考文件和脚本源码完成，结论附出处；
关键出处由 Claude 复核，复核结果见第 6 节。dflow 的 9 组脚本测试在本机全部通过。

下文 `P/` 指 pstack 仓库根目录，`D/` 指 `skills/dflow/`。

## 1. 总评

dflow 覆盖了 pstack 处理单个任务的全流程：调研、讲解、方案、评审、影响面、排查、
实施、验收、无人值守、决策日志、复盘、交接、提交和调优都有入口。其中无人值守的
状态管理、并行落地前的检查、中文去 AI 腔检测，dflow 由脚本和测试保证，比 pstack
只写在文字里的要求更严。

dflow 没有覆盖 pstack 的规模化能力：多候选竞争和评选（arena）、多个审查者组成的
审查面板、项目级多 PR 编排、由云端 agent 做的独立真实环境验证和自动合并。其中一部分
依赖 Cursor（云 agent、按角色配置模型、`control-ui`），在 Claude Code 里无法等价实现；
另一部分是你此前的取舍（多方案只在点名时做，push、PR、合并要先问）。

所以 dflow 可以替代你日常使用的 pstack 部分，不能替代它的大型项目编排部分。

## 2. 逐项对比

“机制”一列：文字 = 只靠 agent 遵守；脚本 = 有代码执行；测试 = 脚本有自动测试。

| 能力 | pstack | dflow | 结论 | 机制（dflow） |
|---|---|---|---|---|
| 理解代码（how） | 简单/复杂分流，复杂问题拆 2–4 个角度（`P/skills/how/SKILL.md:13`） | 先量文件数和行数再分流；复杂问题由 Sonnet 探索者加 codex 并行，主会话自己读主路径（`D/playbooks/research.md:10`） | 等价，dflow 的门槛更明确 | 文字 |
| 追溯动机（why） | 先建 Git/PR 锚点，再按七类来源各派一个调查者（`P/skills/why/SKILL.md:25`） | 同样先查 blame、log、PR，再查可接的来源，缺失的写“无此来源”（`D/playbooks/research.md:38`） | 目标等价，pstack 的来源清单更全 | 文字 |
| 讲解学习 | 组合 how 和 why，分层讲，空间问题配图（`P/skills/teach/SKILL.md:9`） | 先取事实再讲最小完整解释，三个部件以上用逐步图（`D/playbooks/teach.md:6`） | 主体覆盖，教学手段较少 | 文字 |
| 方案与业内调研 | 非平凡架构至少两个结构不同的候选，再交给 arena 评选（`P/skills/architect/SKILL.md:21`） | 需求、方向、计划三段；业内做法走 prior-art；定稿前跨模型评审（`D/playbooks/plan.md:10`） | dflow 默认不做多候选（你选的“点名才做”） | 文字 |
| 架构分析 | ground → sketch → agree → implement，先过设计红线 | 新增模块或跨模块重构前先跑 `references/sketch.md` 和设计红线（`D/playbooks/build.md:10`） | 有“先定结构”，没有强制双候选 | 文字 |
| 方案评审 | interrogate：多个模型并行审同一份改动，按一致程度分级（`P/skills/interrogate/SKILL.md:25`） | 一个异模型（codex）只读审查，主会话独立审并核实每条（`D/playbooks/review.md:12`） | dflow 是一个第二意见，不是审查面板 | 文字 |
| 影响面 | blast-radius：找 grep 看不到的风险，大改动多模型分析（`P/skills/blast-radius/SKILL.md:15`） | 存量数据、配置、外部读者、时序、反射引用；5 级证据；改契约时强制跑（`D/references/impact.md:15`） | 等价，dflow 的证据等级和触发条件更明确 | 文字 |
| 排查修复 | 同一表面复现、二分假设，可用 `/loop` 长期排查（`P/skills/poteto-mode/playbooks/bug-fix.md:3`） | 同一表面复现、逐步排除；第二次修复失败要跨模型复核；超过一小时记决策日志（`D/playbooks/debug.md:6`） | 等价，dflow 的二次失败规则更明确 | 文字 |
| TDD 与测试质量 | 便宜时先写失败测试（`P/skills/tdd/SKILL.md:9`） | 同上，另列出“功能删掉仍会通过”的坏测试形态（`D/principles/test-behavior.md`） | dflow 更具体 | 文字 |
| 验收 | 多 PR 计划要求 unit/live/perf 都有，live 十个场景带截图；`check-plan.mjs` 静态检查计划结构（`P/skills/poteto-mode/scripts/check-plan.mjs:121`） | 每条验收找真实驱动方式，用户可见的必须走真实路径（`D/playbooks/verify.md:7`） | 单项验收接近；项目级 pstack 更强，dflow 没有计划检查脚本 | 文字 |
| 验证 skill | 生成 `verify-*`，并有单独的维护流程 maintain-verification-skill（`P/skills/maintain-verification-skill/SKILL.md:23`） | 能生成 `verify-*` 并自证一次（`D/references/create-verification-skill.md:19`） | 生成接近，dflow 缺维护流程 | 文字 |
| 原型与多方案 | arena：候选隔离、并行、异模型评审、选底稿再嫁接长处（`P/skills/arena/SKILL.md:11`） | 只做视觉原型，2–3 个 HTML 变体（`D/playbooks/prototype.md:7`） | dflow 明显较弱 | 文字 |
| 实施与并行 | feature、multi-phase、autopilot、orchestrate，可到几十上百个 agent（`P/skills/poteto-mode/SKILL.md:123`） | 按可验证单元提交；你说“并行”时最多 3 个 worktree worker，脚本检查路径重叠、越界、落地冲突、清理边界（`D/scripts/parallel.sh:50`） | 小中型并行 dflow 更严；大型编排 pstack 强得多 | 文字 + 脚本 + 测试 |
| 无人值守 | autonomous-run、pause、pickup，靠 `/loop` 和云 agent | 清单、租约、截止时间、gate/默认/死路、暂停接手、caffeinate、通知、收尾检测（`D/playbooks/unattended.md`、`D/scripts/run-state.sh:44`） | 单次运行 dflow 更严；多天多 PR 的项目 pstack 更强 | 文字 + 脚本 + 测试 |
| 决策日志与复盘 | show-me-your-work：TSV、对照会话记录对账、异模型审查（`P/skills/show-me-your-work/SKILL.md:34`） | 同样的 TSV；`timeline.py --say` 合并主会话、子 agent 和对话文字，危险命令扫描，提交对账，`/dflow 复盘`（`D/references/decision-log.md`） | dflow 更严 | 文字 + 脚本 + 测试 |
| 进展与交接 | ketchup、session pickup，可从云 agent 链接接手 | 进展分清“只有你能做的”和“我还能做的”；交接说明结构固定（`D/playbooks/status.md`、`D/playbooks/handoff.md`） | 交接 dflow 更结构化；接手范围 pstack 更广 | 文字 |
| 提交与 PR | 整理提交历史、babysit CI 和评论、云 agent 逐 PR 验证后自动合并（`P/skills/poteto-mode/playbooks/shipping.md:7`） | 本地按功能提交；push、开 PR、合并都先问（`D/playbooks/ship.md:7`） | 跟进 PR 接近；自动交付是有意不做 | 文字 |
| 写作与去 AI 腔 | unslop 规则加 technical-writing 写作体系 | 中文化的 unslop，`slop-check.sh` 按词表报命中行（`D/scripts/slop-check.sh`） | 中文检测 dflow 更强；英文技术写作 pstack 更全 | 文字 + 脚本 + 测试 |
| 调优与教训 | correct、reflect，多角色反思 | 结构 → 检查 → 测试 → 文字，新检查须在真实历史错误上先失败（`D/playbooks/tune.md:7`） | 落地门槛 dflow 更明确；多角色反思 pstack 更强 | 文字 |
| 原则 | 约 25 条，含领域建模、边界、类型、幂等、迁移、共享状态 | 11 条，偏证据和流程（`D/SKILL.md` Principles） | dflow 更窄 | 文字 |
| 安装与配置 | setup-pstack 探测模型、按角色和预算写配置 | 无配置入口，跨模型固定用 codex / claude CLI | dflow 缺可配置性 | 无 |
| 周报 | 无对应 | `dflow-report` 按时间窗从 Git 生成进展报告 | dflow 独有 | 文字 |

codex 的维度表没有提到以下 pstack skill，这里补充：

- `hillclimb`（性能调优循环）：你决定暂不加入。
- `swarm`（N 个 worker 并行再汇总）：dflow 只在复杂调研和并行实施两处使用。
- `recall`（从历史会话和共享记录重建上下文）：dflow 没有，最接近的是“进展”和“交接”。
- `bro`、`in-your-own-words`（用白话复述）：对应 dflow 的“对齐目标”原则和“讲解”。
- `no-comments`（代码注释审查）：dflow 没有。
- `automate-me`（把个人习惯写成 skill）：dflow 本身就是这件事的产物，后续修改走“调优”。
- `typescript-best-practices`、`make-bot-ui`：分别针对特定语言和产品，不适用。

## 3. dflow 较弱的地方

按影响从大到小排列，括号里是 codex 给的最小补法。

1. **项目级多 PR 编排**：dflow 只有单次无人值守，加最多 3 个并行 worker。
   （补法：先做一个只在本地编排的剧本，复用清单、单元表和决策日志，不自动 push 或合并。）
2. **多候选竞争和评选（arena）**：方案默认只出一版，原型只做视觉变体。
   （补法：加 `references/arena.md`，先只用于方案和架构草图：候选各自隔离、给出评分标准、由异模型评审、主会话最终裁决。）
3. **项目级验收门**：没有 pstack `check-plan.mjs` 那样的计划结构检查。
   （补法：加一个计划检查脚本，校验每条验收都有驱动方式、期望结果、证据位置，用户可见项都有真实路径证据。）
4. **验证 skill 的维护**：只有生成，没有后续维护流程。
   （补法：加一个维护剧本，逐个功能核对源码路线并真实驱动一次，结论为 clean / changed / blocked。）
5. **原则较窄**：优先补领域建模、边界纪律、幂等、共享状态隔离四条，并绑定到具体触发点。
6. **宿主能力探测**：跨模型审查、loop、通知、浏览器驱动是否可用，现在散落在各剧本里各自降级。
   （补法：加一个 doctor 脚本统一检测。）

## 4. dflow 更强的地方

1. **无人值守的运行状态由脚本管**：租约、清单哈希、截止时间、未记日志的提交、越界文件、
   caffeinate 生命周期、危险命令扫描（`D/scripts/run-state.sh`、`D/scripts/timeline.py`）。
   pstack 在这方面只有文字规范。
2. **并行落地前的检查**：路径重叠、allow/protect、base 是否为分支祖先、改动文件是否越界、
   冲突时回滚、清理时保留未落地的提交（`D/scripts/parallel.sh:58`，有测试）。
3. **决策日志可以机械核对**：时间线把会话、子 agent 和对话文字合在一起，逐个提交对账，
   复盘时由异模型审查。在 asset-platform 那次 m1-m4 运行上实测，查出了日志外的提交
   和没有执行记录的“已通过”。
4. **中文去 AI 腔可以自动检测**：词表、脚本和 68 项测试。
5. **测试质量规则更具体**：明确列出“功能删掉仍会通过”的几种测试写法。
6. **权限边界更保守**：push、PR、合并、改写历史一律先问，与你的 AGENTS.md 一致。

## 5. 有意不做的差异

| 差异 | 是否合理 | 原因 |
|---|---|---|
| 云 agent 逐 PR 独立验证并回写结论 | 合理 | Claude Code 的本地子 agent 没有独立的云环境和 PR 身份 |
| Origin forge | 合理 | 外部基础设施，不是工作流本身的一部分 |
| 自动 push、开 PR、合并 | 合理 | 你的规则要求先问 |
| 危险命令改为收尾时检测，不实时拦截 | 合理，但要知道代价 | 你选择去掉守卫钩子；命令执行后才会被发现 |
| 多方案只在点名时做 | 你的选择 | 默认精简；代价是第 3 节第 2 条 |
| 不照搬“十个 live 场景” | 合理 | 场景数量应按风险定，不应写死 |
| Codex 宿主里不支持并行 | 可以接受 | 依赖 Claude 的 worktree 子 agent；`D/references/parallel.md:23` 已写明 |

## 6. dflow 内部不一致之处

codex 提出、经 Claude 复核属实的：

1. **dflow 自己的参考文件有 slop 命中**：
   - `references/create-verification-skill.md:13,21,24`
   - `references/acceptance.md:26`
   - `references/plan-shape.md:66,68,71`
   
   这些都是长破折号（规则 13）。SKILL.md 要求给别人看的文字都过 slop-check，但测试只检查词表本身，没有扫 dflow 自己的文件。
   （补法：加一项测试，扫描 dflow 自己的文件。）
2. **无人值守依赖 Claude Code**：`run-state.sh` 用 `CLAUDE_CODE_SESSION_ID` 和 `CLAUDE_PID`。
   入口没有写明“Claude Code 完整，Codex 降级”。
3. **跨模型审查是文字约定**：没有统一的命令包装和失败分类，不可用时只写“未审查”。
4. **`parallel.sh cleanup`**：会删除已落地 worktree 里的未跟踪文件，删前只打印清单，不另存。
5. **SKILL.md 说“任何临时文件都不写 `/tmp`”**：但脚本测试用 `${TMPDIR:-/tmp}` 建测试目录。
   两者用途不同，是规则措辞过宽，不是风险。

## 7. 复核说明

- **抽查了 codex 的引用**：slop 命中、并行上限 3、Codex 不支持并行、`check-plan.mjs`、
  maintain-verification-skill 都对得上。
- **codex 只读沙箱里跑不了部分测试**：需要建临时 Git 仓库的测试在它的沙箱里失败，
  原因是权限不够。本机实跑 9 组全部通过：
  log 14、parallel 26、run-state 32、scratch 5、slop-check 68、timeline 31，
  以及旧体系的 arm、check、guard。
- **pstack 的 TypeScript 测试**：缺依赖，没跑；pstack 侧的“测试”只指读过测试源码。
- **codex 原文**：会话 scratchpad 的 `compare-final/codex.md`。
