# pstack 场景组 2：构建 + 清理 + 验证 + 发布

分析对象：pstack（Cursor 插件，MIT），对照 devflow 现有技能。只读分析，未改任何源文件。

## 约定

- `PS/` = `/private/tmp/claude-501/-Users-lionoggo-Workspaces-devflow/a7a7d076-1990-416c-a333-bdfb06b80744/scratchpad/plugins/pstack/`
- `PM/` = `PS/skills/poteto-mode/`
- `DF/` = `/Users/lionoggo/Workspaces/devflow/skills/`
- 引用格式 `文件:行号`。标"推测"的是未在当前环境验证的判断。
- 机制类型：纯提示词 / 子 agent 并行 / 多模型 / 脚本 / 依赖 Cursor 特性。

## 先讲结论：与用户全局规则的冲突清单

pstack 的默认姿态是"高度自治、能做就做"（`PM/SKILL.md:83`："Reversible work and external actions ... proceed without asking"），和用户规则有系统性冲突。重建时这些点必须改写，不能照搬：

| # | pstack 做法 | 出处 | 冲突的用户规则 |
|---|---|---|---|
| C1 | 每个 PR 都"从 main 拉一个 git worktree 工作"，多个子任务各开 worktree | `PM/playbooks/opening-a-pr.md:5`；`hillclimb.md:12`；`visual-parity.md:7` | 未经要求不创建/切换 worktree |
| C2 | 子任务之间 `git fetch && git reset --hard origin/<branch>`；"Snarled worktree: reset from main" | `opening-a-pr.md:5` | 丢弃未提交改动前必须列出并确认 |
| C3 | "Commit liberally"；hillclimb 每个被接受的尝试自动提交 | `feature.md:12`、`opening-a-pr.md:7`、`hillclimb.md:15` | 提交前除非当前请求明确要求，否则先确认 |
| C4 | "Rebase into small, ordered commits"、amend | `feature.md:14`、`refactoring.md:14`、`opening-a-pr.md:7` | 重写历史属于提交类操作；devflow-commit 明确禁止 amend/改写历史（`DF/devflow-commit/SKILL.md:17`） |
| C5 | 开 PR 不询问，且"Open every PR ready, never as a draft" | `opening-a-pr.md:30`；每个 playbook 末尾都"Run Opening a PR" | 推送、外部发布前先确认 |
| C6 | babysit 自动 push 修复波次、在 review 线程上发回复、给 bugbot 驳回 | `babysit.md:11`、`babysit.md:20` | 推送、外部发布前先确认 |
| C7 | shipping 自动 rebase、push、retarget、squash merge，并把验证结论贴到 PR 上 | `shipping.md:7`、`shipping.md:10-11` | 推送/外部发布/不可逆操作前确认（用户说"land the stack"可算明确授权合并，但中间的 push 和评论仍需逐项确认范围） |
| C8 | worktree 清理："clean and merged and not-in-use proceeds"，`git worktree remove --force`、`rm -rf` | `worktree-cleanup.md:6-7` | 删除前列出具体内容并等待确认 |
| C9 | "Mandatory: no skip-with-reason escape" 强制委派子 agent 写代码 | `feature.md:12` | 用户规则：只有能实质降低总成本时才用子 agent |
| C10 | 默认模型 grok-4.7 + claude-opus 跨家族 | `PS/skills/setup-pstack/SKILL.md:49-65` | 用户规则：子 agent 默认 Opus 或更低，Fable 只用于重大架构设计；Claude Code 无 grok |
| C11 | 回复、PR 文案的写作规则全部面向英文（禁 em dash、STE 词汇） | `PS/skills/unslop/SKILL.md:31`、`technical-writing/SKILL.md:65-74` | 用户要求始终简体中文回复（PR/commit 用英文可保留，见下） |

一个对齐点：PR 标题和 commit subject 用 Conventional Commits `type(scope): subject`（`opening-a-pr.md:11`），与用户的 Git 提交规范一致，可以直接沿用。

---

## 一、构建

### 1. 做新功能（Feature）

1. **问题**：我要加一个新行为，希望设计先想清楚、实现有人复核、最后在真实界面验证过。
2. **pstack 解法**：`/poteto-mode` 路由到 Feature（`PM/SKILL.md:131`）。步骤（`PM/playbooks/feature.md:5-17`）：
   - `how` 摸清子系统 → `architect` 并行设计探索；
   - 写"吞吐检查点"四项：阻塞前置步骤、可并行工作流、共享可变状态、最小安全拆分，不适用的写 `n/a: <reason>` 不得删（`feature.md:7-11`）；
   - 委派子 agent 写代码，必须先给出数据形状及其组织结构（状态机优于零散布尔、表驱动优于分支），多种合理形状时走 `arena`；"Mandatory"，Laziness Protocol 不能豁免（`feature.md:12`）；
   - 在匹配的界面验证，"Inconclusive 或错界面不算通过"（`feature.md:13`）；
   - rebase 成小而有序的提交，按 sequence-verifiable-units 逐单元构建-验证-提交（`feature.md:14-15`）；有争议的设计先 `interrogate`（`feature.md:16`）；最后 Opening a PR。
   - 代码耦合的工作交给单一 owner，父级只为产出独立工件的切片扇出（`feature.md:19`）。
   - 全局触发：任何代码先命名数据形状（`PM/SKILL.md:21`），跨函数边界先 architect（`PM/SKILL.md:22`）。
3. **机制**：纯提示词骨架 + 子 agent 并行（how/architect/arena）+ 多模型（arena 跨家族 runner 与 cross-judge，`PS/skills/arena/SKILL.md:17,28`）。
4. **Claude Code 映射**：可实现。playbook 作为技能的 references 文件；`Task` → `Agent` 工具，自定义 agent 放 `.claude/agents/`；todo 用 TodoWrite。多模型只能退化为同家族（opus/sonnet），跨家族多样性丢失，除非外接 codex CLI（推测可行，需另建适配）。
5. **成本**：how 1–5 个子 agent（简单题 1 个 explainer，复杂题 2–4 explorer + 1 explainer，`PS/skills/how/SKILL.md:17,24,28`）+ architect/arena ≥2 runner + 1 judge + 1 实现 delegate（或 arena 2+1）+ interrogate 2 个 reviewer（可选）+ no-comments 1 个。合计约 6–14 个子 agent，一个中等功能。
6. **devflow 对应**：`devflow-plan` + `devflow-impl`。impl 已有：不替用户做开放决策（`DF/devflow-impl/SKILL.md:11-12`）、按阶段推进且每阶段检查通过才继续（`:17-18`）、验收标签不得悄悄弱化、端到端承诺要端到端观察（`:21-22`）、委派默认直接做（`DF/devflow-impl/references/delegation.md:3-5`）。差距：没有"先命名数据形状/组织结构"的硬要求；没有吞吐检查点；impl 禁止提交（`DF/devflow-impl/SKILL.md:25-26`），没有"每单元验证后再前进"的交付顺序。
7. **判断**：**改写后采用**。吸收"数据形状先行 + 吞吐检查点 + 错界面不算通过"，丢掉强制委派、arena 默认化、grok 和 commit liberally（C3、C9、C10）。

### 2. 修 bug（Bug fix，含 /tdd 与 fix-root-causes）

1. **问题**：有个缺陷，要先复现、找到真正原因、做最小修复，并拿出"修前红、修后绿"的证据。
2. **pstack 解法**（`PM/playbooks/bug-fix.md`）：
   - 科学态度：每行上线代码都要追溯到运行时证据；"可能有帮助"的双保险是假设不是修复；证据推翻假设时，回滚它引出的改动；只上证据支持的最小改动（`bug-fix.md:5`）。
   - 自己在匹配界面复现，即使调试协议说让用户复现；只有在控制面确实够不到时才问用户，且要先尽力驱动（`:7`）。
   - 二分定位：列候选假设，每轮选最能缩小问题空间的切分，拿运行时证据排除；状态不清就加日志；长时间排查用 Cursor `/loop`（`:8`）。
   - 跨函数边界先 architect，再委派实现（`:9`）；同界面验证，原复现通过；"单测只证明分支行为，不证明 bug 消失"（`:10`）。
   - 提交顺序：失败的复现先进历史，修复在上（`:11-12`）。
   - `/tdd`：仅在测试路径便宜清晰时写失败测试，先跑确认"因预期原因失败"，再修，再跑（`PS/skills/tdd/SKILL.md:15-20`）；"宁可不加测试也不加坏测试"（`:26`）；不得改测试去迁就错实现（`:30`）。
   - fix-root-causes：不加 nil 守卫消音；按模式 grep 修全部实例；深挖才找到的关键事实要提议一个常驻信号；重启类 bug 先怀疑持久状态（`PS/skills/principle-fix-root-causes/SKILL.md:16-24`）。
3. **机制**：纯提示词为主；how/why 子 agent 并行；可选 architect 多模型；`/loop` 依赖 Cursor（Claude Code 有同名 `/loop` 技能）。
4. **映射**：可实现。`/loop` → Claude Code 内置 loop 技能；复现界面 → Claude in Chrome / 内置浏览器 / Playwright MCP / tmux（推测按项目选）。
5. **成本**：how 1–5 + why 若干（推测 2–4 investigator + 1 synthesizer）+ 可选 architect 3 + 实现 1 + no-comments 1，约 3–14 个子 agent。小 bug 实际可压到 0–2 个。
6. **devflow 对应**：`DF/devflow-debug/SKILL.md`（25 行）。已有：只修问题本身不加防御代码（`:8-10`）、修后重跑复现和测试（`:11-12`）、只问原因时不改文件（`:13`）、基线用 `git show`（`:14-15`）。差距：没有"自己先复现"的硬要求、没有二分/排除法、没有"被推翻的假设要回滚其改动"、没有失败测试先行和提交顺序、没有按模式全局修。
7. **判断**：**改写后采用**。这是本组性价比最高的纯提示词收益之一；提交顺序部分改成"暂存/建议顺序，提交仍走 devflow-commit 并确认"。

### 3. 重构（Refactoring）

1. **问题**：只改结构不改行为，要能证明行为没变，而且改完确实更好读。
2. **pstack 解法**（`PM/playbooks/refactoring.md`）：
   - 发现缺功能或真 bug 就拆出去，先发结构改动（`:5`）；
   - 先钉住行为契约：特征测试/快照/等价对拍；"类型检查和 lint 不算钉住"（`:7`）；
   - 命名缺失的结构，重塑必须删分支或删非法状态，不能只加间接层（`:8`）；先减后加（`:10`）；
   - 小步迁移，API 重塑同一波迁完所有调用方并删除旧 API，不留兼容垫片；改名要对实际文件逐个核查（字符串、文档里的引用容易漏）（`:11`）；
   - 用真实工件证明行为不变，大改动跑等价检查（`:12`）；
   - 价值判断：若 diff 没在任何地方降低阅读负担就回滚（`:13`）；提交顺序：先删减、再重塑、再清理（`:14`）。
3. **机制**：纯提示词；可选 architect（多模型）、委派 1 个子 agent 做机械改动。
4. **映射**：完全可实现，纯提示词。
5. **成本**：how 1–5 + 可选 architect 3 + 1 delegate，约 2–9；小重构可 0–1。
6. **devflow 对应**：无专门技能，落在 `devflow-impl` 通用流程。差距：无"先钉契约"、无"不降低阅读负担就回滚"、无"同波删旧 API"。
7. **判断**：**改写后采用**，作为 devflow-impl 的一个 references 小节（约 15 行），无需独立技能。

### 4. 性能问题（Perf issue + benchmark-checklist）

1. **问题**：某处慢，要用测量驱动修复，并保证报出来的数字可信。
2. **pstack 解法**：
   - Perf issue（`PM/playbooks/perf-issue.md`）：先抓基线 trace，并用 benchmark-checklist 审查基线和之后每个数字（`:5`）；"不跑就别声称性能上限"（`:6`）；按"性能口诀"从便宜到贵：不做 → 不重复做 → 少做 → 晚做 → 用户看不见时做 → 并发做 → 做得更便宜，满足目标即停（`:7-16`）；修后再抓 trace，把工件转 sqlite/diff 比较（`:17-19`）；PR 引用测量（`:20`）。
   - benchmark-checklist（`PS/skills/benchmark-checklist/SKILL.md`）：跑之前先写下要发布的那句结论（`:15`），看 `uptime`/核数（`:17`）；七问：为什么不是翻倍（找限制因素）、是否按生产调优、是否突破物理上限、是否报错、是否可复现（≥5 次交替 A/B，报中位数和区间）、端到端是否重要、工作是否真的发生（`:21-27`）；不能命名限制因素、某侧未调优、或第 4/7 问没查，就判 inconclusive（`:33`）。
3. **机制**：纯提示词；perf 可选 architect 与 1 个实现 delegate。
4. **映射**：完全可实现。benchmark-checklist 是语言无关的纯文本，可原样搬（`nproc` 在 macOS 上需改为 `sysctl -n hw.ncpu`）。
5. **成本**：0–1 个子 agent（实现）+ 可选 architect 3；主要成本是重复测量的运行时间。
6. **devflow 对应**：无。devflow-verify 的"关键约束的证据要能区分正确实现和看起来一样的廉价实现"（`DF/devflow-verify/SKILL.md:86-87`）思路相近，但不覆盖测量方法。
7. **判断**：benchmark-checklist **照搬**（纯提示词、零依赖、防止最常见的假提速）；perf-issue **改写后采用**（口诀和"基线先行"并入 debug/impl，去掉固定委派）。

### 5. 指标爬坡（Hillclimb）

1. **问题**：要把一个指标持续推到目标，每次只试一个改动，留下可审计的实验记录。
2. **pstack 解法**（`PM/playbooks/hillclimb.md`）：先确认有复现用户抱怨的工作负载，否则先修复现（`:7`）；停止谓词要同时有目标和最少尝试次数（如"比基线好 50% 且至少 10 轮"）（`:7`）；构建测量 harness、证明敏感度、冻结，打印错误数和工作量计数，中位数采样（`:8`）；`decision.tsv` 每次尝试一行，放在仓库外（`:9`）；每个假设要指名具体机制（`:10`）；每轮一个子 agent 实现、前后测量、跑回归门、只接受超出噪声的改进、否则完整回滚，接受即提交、`git add <files>` 不用 `-A`（`:11-15`）；平台期要换类别或组合近似成功项，不得放宽谓词（`:17-18`）。
3. **机制**：子 agent 串行/并行（多假设时并行，各自 worktree）+ 脚本（harness、show-me-your-work 的 log.sh）+ 无人值守时借用 autonomous-run 唤醒机制。
4. **映射**：可实现。唤醒可用 devflow 已有的 `devflow-autorun` / `/loop`；并行 worktree 违反 C1，应改为串行；每轮自动提交违反 C3，需在启动时一次性取得"本次实验允许提交到当前分支"的明确授权，或改为只记录补丁、结束后统一确认提交。
5. **成本**：每轮 1 个子 agent + N 次测量；≥10 轮即 ≥10 个子 agent，是本组最贵的场景之一。
6. **devflow 对应**：无直接对应；`devflow-autorun`/`devflow-autorun-tick` 提供了循环骨架（技能列表中可见）。
7. **判断**：**改写后采用（低优先）**。纪律本身（冻结 harness、一改一测、保留/回滚、决策日志）很好，但使用频率低；等 autorun 稳定后作为它的一种 run 类型加入。

### 6. 诊断不修复（Runtime forensics / Trace forensics）

1. **问题**：内存泄漏、空转 CPU、卡顿，或手里已有一个 profile 文件，只想知道原因落在哪行源码。
2. **pstack 解法**：
   - Runtime（`PM/playbooks/runtime-forensics.md`）：在活进程上抓 CPU profile / heap snapshot / CDP trace（`:5`）；大工件交给子 agent 解析，主线程只留结论（`:6`）；通过 CDP eval 注入探针或热修来证明机制（`:7`）；映射回文件/符号/行（`:8`）；交付诊断不修复（`:11`）。
   - Trace（`PM/playbooks/trace-forensics.md`）：工件是固定数据集，只读不重跑（`:5`）；先转 sqlite 再读（`:8`）；没有源映射的帧"还不算诊断"（`:10`）；没有成对采集就标为"最强假设"而非确认原因（`:11`）。
3. **机制**：纯提示词 + 1 个解析子 agent；Runtime 依赖 CDP（Chromium/Electron/Node 调试端口）。
4. **映射**：Trace 完全可实现。Runtime 需要 Chrome DevTools MCP 或 `node --inspect` + 脚本（推测，需按项目确认）。
5. **成本**：1–2 个子 agent。
6. **devflow 对应**：`devflow-debug` 部分覆盖（"证据"字段），但没有工件处理方法。
7. **判断**：**改写后采用**，合并为 devflow-debug 的一个 references 文件（"拿到 profile/trace 怎么读"），不单列技能。

---

## 二、验证

### 7. 在真实界面上验证（prove-it-works / 完成条件 / 证据形式）

1. **问题**：别跟我说"编译过了"，要拿真实运行的证据，而且我能自己复查。
2. **pstack 解法**：
   - prove-it-works：检查真实对象而非代理（进程存活要直接查、读真实值而非缓存）；验证失败时先怀疑观察方法（`PS/skills/principle-prove-it-works/SKILL.md:13-16`）；最强证明是可重跑的确定性脚本，输出留作工件（`:20`）。
   - 指南：首个 prompt 写明完成条件（`PS/docs/guide/06-verify-and-ship.md:11-17`）；按改动类型匹配检查：CLI 跑真命令、UI 走流程、解析器重放输入、性能比 profile、存储读回写入值（`:19-25`）；"自信但无证据的回复是红旗"（`:17`）。
   - poteto-mode 回复规则：每个结论同句标注"测得/推断/猜测"，能自己跑的检查不要丢给用户（`PM/SKILL.md:111`）。
   - test-behavior-not-implementation：若所有导入函数返回 undefined 测试仍会通过，就重写或删掉；列出了 `toBeDefined`、只断言调用、用被测代码算期望值等反模式（`PS/skills/principle-test-behavior-not-implementation/SKILL.md:9-19`）。
3. **机制**：纯提示词。
4. **映射**：完全可实现。
5. **成本**：0 个子 agent。
6. **devflow 对应**：`DF/devflow-verify/SKILL.md` 在这方面比 pstack 更系统：标准来源优先级（`:49-59`）、证据层级（`:17-19`）、四类失败分类（`:73-74`）、只读验证子 agent 只给标准不给实现推理（`:32-35`）、四档结论定义（`:108-112`）、验收矩阵（`DF/devflow-verify/references/acceptance.md`）。差距：没有"脚本化检查、留工件"的偏好；没有"测试若在 undefined 下仍通过就是坏测试"这一条具体判据；没有项目级控制技能可调（见场景 9）。
7. **判断**：devflow-verify **保留为主体**；从 pstack **照搬** test-behavior 判据和"script the check"两段（各约 5 行）。

### 8. 像素级视觉一致性（Visual parity）

1. **问题**：迁移样式系统或组件时，要证明新旧渲染像素级一致。
2. **pstack 解法**（`PM/playbooks/visual-parity.md`）：先建截图基线 harness，"没有基线就没有一致性结论"（`:5`）；禁止改 harness、改基线、为过 diff 改组件结构，基线看起来不对就停下问（`:6`）；逐组件迁移，跨 worktree 并行，共享原语先迁（`:7`）；非零 diff 即失败，`/loop` 到零（`:8`）。
3. **机制**：纯提示词 + 截图/图像 diff 脚本 + 并行 worktree。
4. **映射**：可实现（Playwright 截图 + pixelmatch，推测）；并行 worktree 违反 C1，需改串行。
5. **成本**：每组件 1 个子 agent + 截图运行。
6. **devflow 对应**：无。
7. **判断**：**不需要**（现阶段）。场景窄；"不准改基线/harness 来过测试"这条反作弊规则值得写进 devflow-verify 的 harness 分类说明里。

### 9. 为项目生成验证技能（create-verification-skill）

1. **问题**：每次让 agent "在 app 里验证"都要重新摸索怎么启动、怎么驱动，我想要一份项目内固定的驱动说明书。
2. **pstack 解法**（`PS/skills/create-verification-skill/SKILL.md`）：
   - 访谈仓库而不是用户：界面、启动、驱动方式（先找现有 Playwright/expect 等 harness，再选通用方案）、可采证据、能否双实例隔离（`:13-19`）；仓库跑不起来就先修或精确报告（`:21`）。
   - 生成 `.cursor/skills/verify-<app>/SKILL.md`，必须有 Launch / Doctor / Drive / Evidence / Cleanup / Helpers 六节；Launch 要从空数据目录到可用状态，"就绪指可用，不是进程有应答"；Doctor 是只读健康检查；Drive 用稳定句柄（ARIA、data 属性）；Evidence 要走真实用户路径、记录动作和结果状态、校验副作用、dry-run 要实际观察它跳过了什么；Cleanup 只杀自己启动的进程、证据必须保留（`:25-32`）。
   - 种功能地图：`features/README.md` + 每功能一个文件，四个固定 H2；前置条件缺失就报失败，不得削弱旅程（`:36`；示例 `references/feature-map-example/README.md:33-42`、`create-note.md`、`search.md`）。
   - 交付前自证：按生成的说明完整跑一遍并确认清理后证据仍在；"从没执行过的技能只是草稿"（`:40`）。
3. **机制**：纯提示词（主线程长任务），生成物是技能文件 + 可选辅助脚本。
4. **映射**：可实现，路径改为 `.claude/skills/verify-<app>/`。Claude Code 内置 `run` 技能会"先找已覆盖启动 app 的项目技能"（见本会话技能列表），生成的 verify 技能可直接被它和 devflow-verify 复用。驱动层用 Playwright MCP / Claude in Chrome / tmux（推测按项目选）。
5. **成本**：0 个子 agent；一次较长的主线程会话（启动、调试、跑一遍）。
6. **devflow 对应**：无。devflow-verify 每次都临场找证据路径，"无法观察就给手工清单"（`DF/devflow-verify/SKILL.md:69-72`），这正是该技能要消除的人工环节。
7. **判断**：**改写后采用**，本组第一优先。改写点：路径换 `.claude/skills`；生成后作为未提交改动交给用户，由 devflow-commit 在确认后提交；Doctor/Evidence 规则原样保留。

### 10. 维护验证技能（maintain-verification-skill）

1. **问题**：app 变了，验证技能和功能地图跟着过时，需要定期对账。
2. **pstack 解法**（`PS/skills/maintain-verification-skill/SKILL.md`）：三种结局 clean / changed / blocked 必选其一（`:13-17`）；只改验证技能目录，绝不改产品代码，产品回归要报告而不是改文档掩盖（`:21`）；每个功能文件一个只读源码阅读子 agent 并行（`:29`）；协调者独自做一次覆盖全部功能的实机驱动，三条不变量：可疑后先 doctor、证据经得起清理、驱动残留必须清掉（`:33`）；changed 时只开一个 PR（`:37`）。指南建议每天跑、最好定时（`PS/docs/guide/06-verify-and-ship.md:88`）。
3. **机制**：子 agent 并行（每功能 1 个）+ 主线程实机驱动 + 自动开 PR。
4. **映射**：可实现；定时可用 Claude Code 的 `/schedule` 或 `/loop`（推测）。"一个 PR"违反 C5，改为"产出未提交修改 + 报告"。
5. **成本**：N 个只读子 agent（N = 功能数，初始 3–5）+ 1 次较长实机会话。
6. **devflow 对应**：无。
7. **判断**：**改写后采用**，在场景 9 落地后再做；去掉自动 PR 和"每天跑"的默认频率，改为手动触发。

### 11. make-bot-ui

1. **问题**：做一个网页按钮，通过 webhook 唤醒 Cursor 里的 Grok Bot。
2. **pstack 解法**：`update_state` 建 webhook routine、`SendToUser secret-request` 收密钥、Tailscale 暴露（`PS/skills/make-bot-ui/SKILL.md:15-23,41-49,75-103`）。
3. **机制**：完全依赖 Cursor 特性（routine、secret-request、Grok Bot）。
4. **映射**：不能直接实现；Claude Code 无对等的 webhook routine（推测可用 `/schedule` 远程 routine 部分替代，但触发方式不同）。
5. **成本**：不适用。
6. **devflow 对应**：无，也不需要。
7. **判断**：**不需要**，与开发流程无关。

---

## 三、清理

### 12. 代码清理（deslop + no-comments / Comment Sicko）

1. **问题**：agent 写的代码有叙述性注释、无依据的防御守卫、死兼容路径，审阅者一看就像没写完。
2. **pstack 解法**：
   - `/deslop` 在 cursor-team-kit 里，pstack 不自带；没有就用自然语言要求"删叙述注释、无依据守卫、死兼容路径、无关改动"（`PS/docs/guide/05-build-and-clean.md:59`）。
   - `/no-comments`：注释必须交给"不是作者"的 reviewer（`05-build-and-clean.md:71`）。派生 `comment-sicko` 子 agent（`PS/skills/no-comments/SKILL.md:19`）。Comment Sicko 只保留五类：许可证头、外部依赖强加的非显然行为、prettier-ignore 和纯风格类 lint 抑制、公共 API 文档注释、解释约束的 issue/RFC 链接（`PS/agents/comment-sicko.md:16-20`）；自家代码的意外行为注释一律删并标 `MUST KILL`，要求通过改名/抽取/类型/重构让行为显然（`:17`）；`@ts-ignore` 等抑制若规则保护正确性就删抑制并标 `MUST KILL`（`:24`）；只报告不改代码（`:30-32`）。
   - 父级复核其报告，拒绝越界删除；"do not remove"类约束注释要提议编码成类型/测试/lint，交互式等批准（`no-comments/SKILL.md:20-23`）。
   - 写注释的日常规则：只为代码表达不了的"为什么"留注释（`PM/SKILL.md:117`）。
3. **机制**：子 agent（1 个 comment-sicko，人格化提示词）+ 可选 architect。
4. **映射**：可实现，`comment-sicko` 放 `.claude/agents/`，`/no-comments` 作技能。Claude Code 内置 `/simplify`（复用/简化/效率清理并直接修改）可替代 deslop 的大部分，内置 `/code-review` 找正确性问题。
5. **成本**：1 个子 agent；若需重塑再加 architect 约 3 个；被拒一次重跑 1 个。
6. **devflow 对应**：无。devflow-impl 只要求"不加计划外的东西"（`DF/devflow-impl/SKILL.md:13-14`），不做事后清理。
7. **判断**：**改写后采用**。deslop 用内置 `/simplify` 顶替；no-comments 保留"由非作者审注释 + 约束编码成检查"两点，人格化措辞可去掉；`MUST KILL` 引出的重构默认只报告，不自动扩大改动面。

### 13. 文字清理（unslop + technical-writing）

1. **问题**：PR 描述、commit body、文档读起来有 AI 腔，啰嗦、空洞。
2. **pstack 解法**：
   - unslop：编号规则表，覆盖 AI 词汇、"serves as"、强行三段、em dash、冒号连接、粗体滥用、谄媚、填充、抽象隐喻名词、被动语态、过度压缩等（`PS/skills/unslop/SKILL.md:17-62`）。
   - technical-writing：四层（Diátaxis 文档模式、Google 开发者文风、STE 一句一指令、Global English 无歧义）（`PS/skills/technical-writing/SKILL.md:30-89`）；PR/commit 适用除 Diátaxis 外的所有层，"PR 正文是一分钟能读完的简报"（`:94`）。
   - poteto-mode 回复也必须按 unslop 写（`PM/SKILL.md:26,101-111`）。
3. **机制**：纯提示词。
4. **映射**：完全可实现。
5. **成本**：0。
6. **devflow 对应**：devflow 各技能都有"结论先行、无内部状态码"的输出模板（如 `DF/devflow-verify/SKILL.md:103-106`），但没有写作风格规范。
7. **判断**：**改写后采用**。英文 PR/commit 正文（用户近期提交都是英文）可直接用 technical-writing 的 STE/Global English 层和 unslop；中文回复需要另写一份中文版"去 AI 腔"清单（em dash 等规则对中文不适用，见 C11）。

### 14. 语言/测试规范（typescript-best-practices）

1. **问题**：TS 代码里的类型纪律（判别联合、品牌类型、禁 `as`、边界解析）。
2. **pstack 解法**：一张规则表（`PS/skills/typescript-best-practices/SKILL.md:12-29`），示例在 `references/patterns.md`（324 行）；frontmatter 用 `paths: ["**/*.ts", "**/*.tsx"]` 但又 `disable-model-invocation: true`，指南说要手动 `/typescript-best-practices`（`PS/docs/guide/05-build-and-clean.md:55`）。
3. **机制**：纯提示词。
4. **映射**：可实现；Claude Code 技能是否支持 `paths` 条件加载需核对文档（推测），也可放进项目 CLAUDE.md 或 `.claude/rules`。
5. **成本**：0。
6. **devflow 对应**：无（devflow 本仓库是 shell + Markdown）。
7. **判断**：**不需要**作为 devflow 核心；有 TS 项目时按项目照搬。

### 15. 提交节奏（sequence-verifiable-units + 提交）

1. **问题**：多步工作要每步可验证，最后的提交顺序本身能讲清楚"先红后绿"。
2. **pstack 解法**：执行上每个单元"已知好状态 → 一个改动 → 跑检查 → 再前进"，先 rebase 到干净主干（`PS/skills/principle-sequence-verifiable-units/SKILL.md:13`）；交付上按证明顺序堆提交：失败测试→修复、删减→重塑、基线→处理、脚手架→功能（`:15`）；落到 playbook 是 commit liberally + rebase（`PM/playbooks/opening-a-pr.md:7`）。
3. **机制**：纯提示词。
4. **映射**：可实现。
5. **成本**：0。
6. **devflow 对应**：`DF/devflow-commit/SKILL.md` 做范围选择、原子拆分、hook 处理，禁止 amend/改历史/push（`:8-17`），比 pstack 更安全。差距：没有"按证明顺序排列拆分后的提交"的指引。
7. **判断**：**改写后采用**。执行部分写进 devflow-impl；交付部分只作为 devflow-commit 拆分时的排序建议，不引入 rebase/amend（C3、C4）。

---

## 四、发布

### 16. 开 PR（Opening a PR）

1. **问题**：改完了，要以审阅者友好的方式开 PR：小、有序、正文说清为什么和怎么证明。
2. **pstack 解法**（`PM/playbooks/opening-a-pr.md`）：
   - worktree 工作、子任务之间 reset（`:5`，见 C1/C2）；commit liberally、rebase 成有序小提交、commit body 不复述 subject（`:7`）；
   - 提交前 `/deslop`、审阅前 `/no-comments`，标题/正文/commit body 用 technical-writing + unslop（`:9`）；
   - 标题 Conventional Commits（`:11`）；正文模板 `## Why` / `## What changed` / `## Scope`（必有）/ `## Tradeoffs` / `## Blast Radius` / `## Verification`，各 1–3 条，正文会成为 squash commit body，控制在约 40 行；长证据放链接工件（`:13-22`）；
   - forge：默认 `gh`，有 Origin CLI 用 Origin，不要求 Graphite（`:24`）；有内置 PR 工具时必须用它（`:26`）；
   - 偏好 5 个窄 PR 胜过 1 个大 PR，stack 用 base 链（`:28`）；一律 ready 不开 draft（`:30`）；
   - 开 PR 不等于开始 babysit，贴 URL 继续干活（`:32`）。
3. **机制**：纯提示词 + `gh` CLI；Origin 和"内置 PR 工具"依赖 Cursor 特性。
4. **映射**：可实现，用 `gh`。删掉 Origin、内置 PR 工具、worktree 段落。
5. **成本**：no-comments 1 个；若由子 agent 开 PR 还要跑 interrogate（2 个 reviewer，`:34`）。主线程开约 1–3 个。
6. **devflow 对应**：无。devflow-commit 明确不 push/不建 MR（`DF/devflow-commit/SKILL.md:3,17`），`wt` 技能也不 push 不建 MR。发布链在 commit 之后断开。
7. **判断**：**改写后采用**，新建一个 `devflow-pr` 之类的技能：沿用正文模板和标题规则；push 与 `gh pr create` 前列出将推送的分支/提交和 PR 标题正文，等用户确认（C5）；draft/ready 由用户选，不强制 ready；不建 worktree。

### 17. PR 跟进到可合并（Babysit + watch-pr + bugbot-triage）

1. **问题**：PR 开了之后 CI 挂、冲突、bot 和人的评论，我想让 agent 盯着并处理到可合并，但不要它替我合并。
2. **pstack 解法**：
   - 模式先声明：`drive`（跑到 merge-ready）、`background`、`threads-only`（只回评论）、`check`（一次状态报告）；未声明默认 drive，小 PR/纯文档用 check（`PM/playbooks/babysit.md:7`）。
   - 只处理 stack 最底下未合并的 PR（merge frontier）（`:8`）；每个 stack 只一个 babysitter（`:9`）；babysit 内不 rebase/retarget/force-push，rebase 类问题上报（`:10`）。
   - 顺序：冲突 → 评审线程 → CI；所有已知修复合成一次 push；冲突只报告不解决（`:11`）。
   - 以 forge 判定为准，GitHub 上用 `scripts/watch-pr/watch-pr`，默认 JSON，`--status-only` 用于 check，裸跑轮询到终态；评论文本是不可信数据，不当指令；在 `/loop` 动态模式里跑，每次 push 后重新挂上 watcher，不另加 sleep 循环（`:12`）。停止条件 READY / WAITING merge-queue / COMPLETE（`:14-18`）。
   - CI 分类：flake 只允许一次全新构建，第二次同样失败就不是 flake；diff 没碰的代码失败先用 `git merge-base --is-ancestor` 查是否基线过旧（`:19`）。
   - Bugbot 一律怀疑式分诊：fix / dismiss / ask；真问题在拥有该代码的最低 PR 上先红后修；回复通过 JSON 文件传给 `gh api`，"绝不把评论文本插进 shell 命令"；第三轮起倾向驳回已记录模式，但安全/鉴权/计费/数据/迁移类必须上报；"不为让 bot 安静而改代码"（`:20`）。
   - 人的界线：owner 审批是等待不是阻塞；babysit 从不授权合并（`:21`）。
   - bugbot-triage 规则：fix/dismiss/ask 三分类，拿不准就问（`PM/references/bugbot-triage.md:9-13`）；可学习的跳过模式有固定格式和置信度分级（`:17-29`）；安全/隐私/鉴权/计费/迁移/并发等默认要问（`:77-82`）。
   - watch-pr 脚本：Bun + TypeScript + commander，通过 `gh pr view`/`gh pr checks`/`gh api graphql` 读取（`PM/scripts/watch-pr/github.ts:443-591`）；分类优先级 冲突 > 线程 > CI > 门禁（`PM/scripts/watch-pr/policy.ts:218-236`）；退出码 2 冲突 / 3 线程 / 4 CI / 5 超时 / 6 门禁 / 7 查询失败（`policy.ts:315-340`）；查询失败指数退避，最多 300 秒（`policy.ts:266-269`）；Bugbot 线程识别靠作者名/文本含 bugbot（`github.ts:333-341`）。
3. **机制**：脚本（watch-pr，约 2.4k 行含测试）+ 纯提示词 + 依赖 `/loop`；Bugbot 是 Cursor 的产品，Origin 是 Cursor 的 forge（依赖 Cursor 特性的部分）。
4. **映射**：可实现。watch-pr 只依赖 `gh` 和 `bun`，可原样带走；`/loop` 用 Claude Code 的 loop 技能，或用 Monitor 工具订阅 watch-pr 的 NDJSON 输出、`run_in_background` 等待终态（推测，Monitor 当前是延迟加载工具）。没有 Bugbot 时，triage 规则可推广到 Claude 的 `/code-review --comment`、Copilot 等 review bot 的评论（推测需要改 `isBugbot` 识别逻辑）。
5. **成本**：0–1 个子 agent；主要成本是轮询唤醒的模型轮次，每次唤醒一轮对话；一个有多轮 bot 评论的 PR 可能是十几到几十轮。
6. **devflow 对应**：无。
7. **判断**：**改写后采用**。watch-pr **照搬**；默认模式改为 `check`（只读报告）和 `threads-only`（起草回复，用户确认后发）；`drive` 中每次 push 与每条线程回复都先列出再确认（C6）；bugbot-triage 的三分类和"高风险必问"直接沿用。

### 18. 合入（Shipping）

1. **问题**：一串 PR 都绿了，要安全地按顺序合进主干，绿不等于安全。
2. **pstack 解法**（`PM/playbooks/shipping.md`）：每个 PR 一个独立验证子 agent，"每个都是 Cursor 云端 agent"，在真实界面上对比 parent 和 head，返回 PASS / PASS+NOTES / FAIL 并贴到 PR；"安全指由没写代码的 agent 给出的结论，CI 绿和 bot 批准都不算"（`:7`）；只合从底部起连续已验证的那一段（`:8`）；用 `git patch-id` 确认结论仍对应当前补丁，rebase 后只有测试/文档差异时还要做两次构建比对噪声（`:9`）；只准备底部 PR、rebase、push、retarget（`:10`）；一次合一个，squash，用户要求时才 `--auto`（`:11`）；每次合并后重算（`:13`）；监视但不动队列（`:14`）。
3. **机制**：子 agent 并行（每 PR 一个，Cursor 云端 agent）+ 脚本（watch-pr `--queued-stack`）+ 依赖 Cursor 特性（cloud agent、Origin）。
4. **映射**：部分可实现。独立验证可用本地后台子 agent；但对比 parent 和 head 需要另一个检出目录，在不建 worktree 的约束下只能 `git archive <sha>` 导出到临时目录（推测可行）；云端 agent 对应 Agent 的 `isolation: remote`（可用性受限）或 `/schedule`（推测）。
5. **成本**：每 PR 1 个验证子 agent + 每 PR 若干次构建 + 长时间监视轮次。
6. **devflow 对应**：无；`wt` 技能明确拒绝本地把功能分支合进 dev/main（技能描述）。
7. **判断**：**不需要**（现阶段）。面向多 PR stack 和团队合并队列，成本高且大量依赖 Cursor；只保留两条思想写进 PR 技能："只有用户明确说合并才合并"和"验证结论用 patch-id 绑定补丁"。

### 19. worktree 与模拟器清理（Worktree cleanup）

1. **问题**：磁盘被一堆旧 worktree 和 iOS 模拟器占满。
2. **pstack 解法**（`PM/playbooks/worktree-cleanup.md`）：记录 `df -h /`，跑只读审计脚本 `worktree-audit.sh` 按大小、年龄、合并状态、未提交改动、PR 状态、最近对话分类（`:3`）；分桶只是建议，用户钉住的会话优先（`:4`）；疑似在用的派子 agent 读会话记录（`:5`）；`wip:N` 必须给 diff 并等决定（`:6`）；`git worktree remove --force` + `rm -rf` + `prune`（`:7`）；再清模拟器、DerivedData、包缓存（`:8`）。审计脚本按 `~/.cursor/projects/<slug>/agent-transcripts` 找最近会话（`PM/scripts/worktree-audit.sh:55-57`）。
3. **机制**：脚本（只读审计）+ 子 agent 并行读会话 + 依赖 Cursor 特性（会话记录路径、侧边栏钉住）。
4. **映射**：审计脚本把会话目录改为 `~/.claude/projects/<slug>/` 即可（推测，Claude Code 会话是 jsonl）；删除步骤必须改为逐项列出后确认（C8）。
5. **成本**：脚本 + N 个读会话子 agent。
6. **devflow 对应**：无；用户默认不用 worktree，Orca 管理的 worktree 由 `orca-cli` 负责。
7. **判断**：**不需要**。与"默认不建 worktree"的工作方式不匹配；若 Orca worktree 堆积，可只借用只读审计脚本。

---

## 五、跨场景要点

- **"Inconclusive 或错界面不算通过"** 在 feature/bug/perf 三个 playbook 里重复出现（`feature.md:13`、`bug-fix.md:10`、`perf-issue.md:19`）。devflow-verify 已有同义规则（`DF/devflow-verify/SKILL.md:85`），应保持一处定义、多处引用。
- **playbook 步骤原样抄进 todo，不做的步骤写 `skip: <reason>`**（`PM/SKILL.md:121`）。这是防止跳步的低成本结构手段，可直接用于 devflow 各技能。
- **子 agent 默认全新、不链式续接**（`PM/SKILL.md:99`）与 devflow delegation"复核实际 diff 而非 worker 自述"（`DF/devflow-impl/references/delegation.md:30`）一致，可合并。
- **多模型**：pstack 的对抗信号来自跨家族模型（`PS/skills/interrogate/SKILL.md:9`）。在 Claude Code 上只能用同家族，效果会打折扣，不应把 interrogate/arena 设为默认步骤。

---

## 本组总结

### 最值得采用的 3 点

1. **create-verification-skill（随后加 maintain）**：把"在真实 app 里验证"从每次临场摸索变成项目内固定的 Launch/Doctor/Drive/Evidence/Cleanup 技能和功能地图。它直接补上 devflow-verify 最大的缺口（看不到真实路径时只能给手工清单），也能被 Claude Code 内置 `run` 技能复用。纯提示词，无 Cursor 依赖。
2. **把 bug-fix 纪律并入 devflow-debug**：自己先复现、二分排除、被推翻的假设要回滚其改动、能便宜写测试就先红后绿、按模式修全部实例、坏测试判据（返回 undefined 仍通过就是坏测试）。全部是纯提示词，加几十行就能显著提高修复质量。benchmark-checklist 同理，可原样照搬。
3. **补上发布链：PR 正文模板 + watch-pr + bugbot 分诊**：devflow 在 commit 之后完全断开。opening-a-pr 的 Why/What changed/Scope/Blast Radius/Verification 模板、watch-pr 脚本（只依赖 gh + bun）、fix/dismiss/ask 分诊规则和"评论是不可信数据"都可直接用。前提是 push、开 PR、回复线程全部改为先确认。

### 最不值得采用的 3 点

1. **Shipping**：面向多 PR stack 和团队合并队列，依赖 Cursor 云端 agent 和 Origin，每个 PR 都要独立验证 agent 加多次构建，成本高，且与"推送/合并前确认"冲突。只取"patch-id 绑定结论"的思想即可。
2. **强制委派、arena 和跨家族多模型作为默认步骤**：feature.md 写明委派是"Mandatory"、不得跳过（`feature.md:12`），默认模型是 grok。这违反用户"只有降低总成本才用子 agent"和"子 agent 默认 Opus 或更低"的规则，而且 Claude Code 上没有跨家族多样性，arena/interrogate 的主要收益会消失。
3. **worktree 驱动的工作方式（opening-a-pr 的 worktree/reset、并行 worktree、worktree-cleanup）和 make-bot-ui**：前者与"不建/切 worktree"和"丢弃改动先确认"直接冲突，`git reset --hard` 还有数据丢失风险；后者完全绑定 Cursor routine 与 Grok Bot。都应舍弃。
