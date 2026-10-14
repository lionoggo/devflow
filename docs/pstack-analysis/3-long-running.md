# pstack 场景组 3：长任务与无人值守 —— 对照 devflow 的分析

> 只读分析。路径约定：`PS/` = `scratchpad/plugins/pstack/`，`PB/` = `PS/skills/poteto-mode/playbooks/`，`DF/` = `/Users/lionoggo/Workspaces/devflow/`。
> 标"推测"的是未在本机实测的 Claude Code 能力或行为，需要验证。

## 0. 先说结论

- pstack 的长任务方案几乎全是**提示词纪律**，结构性的东西只有三样：决策日志脚本 `log.sh`（devflow 已搬）、编排记账 CLI `orch.ts`（只给多天项目用）、Cursor 的 `/loop` 和云端子 agent（宿主能力）。它**没有守卫**，安全靠"可撤销直接做 / 不可逆才停"的授权规则、worktree 或云 VM 隔离，以及"先赢得信任再开循环"（`PS/docs/guide/07-overnight.md:9-16`）。
- devflow-autorun 的三个问题在 pstack 里分别是这样解决的：
  - 守卫没拦下过东西：pstack 根本不设守卫；
  - 启动仪式失效：pstack 没有仪式，只要四行提示（`07-overnight.md:22-27`）；
  - 卡住就收尾：pstack 规定"瓶颈不是停止理由"（`PB/autonomous-run.md:11`），人的问题要么"停放问题、写好默认值、绕开继续做"（`PB/orchestrate.md:30,105`），要么"能用实验回答就不问人"（`poteto-mode/SKILL.md` Non-negotiables 第 2 条）。
- `plan-unattended.md` 覆盖了单任务场景（S1）的核心，以及日志/审计场景（S7）的大半。它漏掉了：
  - 唤醒机制的区分（等事件 vs 定时心跳）；
  - 途中发现的问题怎么处理；
  - 显式暂停和上下文压缩前的检查点；
  - 新会话接手的核对步骤（反而删掉了 autorun 已有的 Resume）；
  - 日志对照对话记录的审计；
  - "先赢得信任"；
  - 卡住后改做别的单元，而不是整轮停；
  - **最关键的一条**：ludus 的真实用法是"一份计划、多个阶段契约"（p0→p1-core→p1-web→…），这是 S4 的轻量版，方案仍然一次只跑一个完成条件，所以"每阶段回来一次"的问题没有解决。

---

## S1. 单任务跑到完成（Autonomous run + 过夜合同）

1. **问题**：我去睡觉，希望 agent 把一个有明确完成条件的任务做完，不要中途停下等我。
2. **pstack 解法**
   - 触发：用户说"run until done""/loop until X""going to bed"（`poteto-mode/SKILL.md:Playbooks` 的 Autonomous run 条目；会话覆盖规则在 `SKILL.md:Autonomy`："Don't stop / going to bed / run until done → keep going"）。过夜合同四行：目标+新 worktree、done means、记决策日志+提交前不用问、`/loop until done`+真卡住几小时后停下写原因（`07-overnight.md:22-36`）。
   - 步骤（`PB/autonomous-run.md:5-11`）：
     1. 先把退出条件写成可检查的谓词；
     2. 选唤醒机制：有事件可等（CI、合并、ref 前进）就派 watcher 子 agent 在事件发生时唤醒，加一个长周期心跳兜底；没有事件就按"结果值得重看"的间隔定时；
     3. 每轮做证据支持的最小改动，对谓词验证，前进就提交，没帮助就丢弃，"可能有用"的保险性改动也要回退；
     4. 途中发现的问题（坏掉的技能、相关 bug、不稳定的验证器、工具故障）自己修，放进单独 PR，不停下问人；只上报不可逆操作、实验解决不了的产品/偏好问题、真正的死路；
     5. 每轮记一行日志；
     6. 谓词满足才停，瓶颈期换思路，绝不放宽谓词。
   - 关键规则：
     - "时长不是完成条件"（`07-overnight.md:118`）；
     - 先赢得信任：先手动做过一次、agent 有你用的工具、每个阶段能叫停、读过几份对话记录并把反复出现的失败做成工具（`07-overnight.md:9-16`）；
     - 只有一个事件 watcher，不另加 sleep 循环（`PB/babysit.md:12`）。
3. **机制**：纯提示词，加 Cursor `/loop`（内置唤醒），可选一个 watcher 子 agent。
4. **Claude Code 映射**：可以实现。
   - 唤醒：
     - 没有事件可等时用 `/loop`（Claude Code 内置 `loop` 技能；不带间隔是动态节奏，带间隔是定时）；
     - 有事件可等时，用 `run_in_background` 的 Bash（例如 `gh pr checks --watch`，或 `until <cond>; do sleep 60; done`），进程退出时会唤醒会话；也可以用 Monitor 工具；
     - CronCreate 适合给长周期心跳兜底（推测：只在会话存活期间有效）。
   - 还可以加一个 **Stop hook** 作为结构性兜底：模型想结束回合时，hook 跑完成条件命令，没通过就带理由阻止结束（推测，需要验证它和 `/loop` 的交互，以及防死循环的计数）。这比 PreToolUse 守卫更对症，因为 ludus 的实际病灶是"过早收尾"，不是"越权"。
   - 防休眠用 `caffeinate`。
5. **成本**：低。一轮就是一次普通编码回合，再加一行日志；watcher 是一个后台进程，几乎不占 token。
6. **devflow 现状和差距**：
   - devflow-autorun + tick 已经有谓词、基线、提交/撤销、每轮一行日志、绝不放宽（`DF/skills/devflow-autorun-tick/SKILL.md:21-61`）。
   - 差距：
     - 有一套启动仪式（契约文件、arm.sh、标记、守卫自检），实测两次失效；
     - 停止条件偏紧："连续 3 轮无进展就停"（tick:57），加上"所有剩余单元都停放了"也停，所以容易早早收尾；
     - 没有事件 watcher；
     - 途中发现的问题没有规则；
     - 没有"先赢得信任"。
7. **判断**：**改写后采用**。照搬提示词纪律；唤醒部分改用 Claude Code 的后台 Bash/Monitor 加 `/loop`；用 Stop hook（可选）替换 PreToolUse 守卫。

## S2. 一队独立 PR 跑到合并（Autopilot-full）

1. **问题**：我有 N 个互不依赖的改动，希望早上醒来全部验证过并合并好。
2. **pstack 解法**（`PB/autopilot-full.md:3-13`）
   - 触发："autopilot this queue""full autopilot"。
   - 规则和步骤：
     - 用户点名的项留给用户，用户要求"先说计划"就只说不做（`:5`）；
     - 每个 PR 一个云端 owner agent，从构建一路做到合并；15 分钟内开 `decisions.tsv`、推首个快照、开 ready PR，之后每个可验证单元推一次；维护 `children.tsv`，记下每个子 agent 的预期时长（`:6`）；
     - 真并行，不叠栈；只有真正重叠的工作才串行（`:7`）；
     - root 只做验证：每个 code-ready SHA 发起 swarm 多路验证（重跑门禁、真实表面上的 live 验证、两路以上 diff 审计、对 trunk 的回归通道），聚合成一个裁决；没有 live 通道就不算干净（`:8`）；
     - 裁决干净后，owner 自己 rebase、确认 merge-tree 干净、squash 合并；然后换一个新 owner 接下一项（`:9`）；
     - root 每小时用 `/loop 1h` 审计一次：从 trunk 重读剧本，只把副作用（commit、push、PR 变化）算作进展，超过预期时长没有副作用就判定卡住，立即换人（`:10`）；
     - 用户喊停时，所有 owner 立即零写入（`:11`）。
3. **机制**：子 agent 并行（Cursor 云端 agent，每 PR 一个）+ 多模型 swarm 验证 + `/loop 1h` 审计 + `gh` 或 Origin CLI。依赖的 Cursor 特性：云端 agent、Bugbot、`cursor-team-kit` 的 deslop/control-ui。
4. **Claude Code 映射**：部分可行。
   - owner 可以用 Agent 后台 + `isolation: "worktree"`，或者 Orca worktree 加 `orchestration` 技能（用户本机已装，自带任务 DAG、worker_done 等待、决策门）；
   - 审计 tick 用 `/loop 1h` 或 CronCreate；
   - 多模型验证用 `codex exec`；
   - 笔记本合盖后继续跑需要云端：`schedule` 技能或 Agent `isolation: "remote"`（推测，可用性受限）。
   - 但是"agent 自己合并"直接违反用户全局规则（推送和外部发布前要确认），worktree 也必须用户明确要求才能建。
5. **成本**：很高。每个 PR 要一个 owner，加 3–5 路以上的验证 agent，再加每小时一次审计；按 pstack 默认，N 个 PR 大约是 N×(1+5) 个 agent 会话。
6. **devflow 现状**：没有对应物。devflow-impl 的 delegation 只覆盖会话内有界的子 agent，而且禁止嵌套（`DF/skills/devflow-impl/references/delegation.md:22-23`）。
7. **判断**：**现在不需要**。它和用户的提交/推送确认规则正面冲突，成本远超 ludus 的实际需要（单人、本地、一次一个契约）。如果以后真有一队独立任务，可以只借两条：每项一个本地分支，以及"只把副作用算进展"的存活判断。

## S3. 线性 PR 栈（Autopilot-stack）

1. **问题**：一串有先后关系的改动，我想早上收到一条验证好的线性栈，自己审、自己合。
2. **pstack 解法**（`PB/autopilot-stack.md:3-16`）：
   - owner 循环和 S2 相同，但不合并；
   - 裁决干净后，按顺序把 PR 追加到一条 base-branch 链上；
   - **只有 root 改拓扑**（rebase 到父分支、`--force-with-lease`、改 PR base），owner 只推自己的分支（`:10`）；
   - trunk 漂移由 root 自底向上 rebase，用 patch-id 规则判断旧裁决是否还有效（`:11`）；
   - 交付物是每个链接都带裁决的栈（`:12`）；
   - 选择规则：互相独立且授权合并时用 full，耦合或用户要先审时用 stack（`:14`）。
3. **机制**：同 S2，再加"单一写者管理拓扑"（`principle-separate-before-serializing-shared-state`）。
4. **Claude Code 映射**：技术上可行（`gh pr create --base`、`git rebase`），但 force-push 和开 PR 都要用户确认。
5. **成本**：高，比 S2 少了合并，多了 rebase 链的维护。
6. **devflow 现状**：没有对应物。ludus 实际是在**一个本地分支**上串行跑多份契约，提交本身就构成线性历史，不需要 PR 栈。
7. **判断**：**不需要**。可以借鉴的只有一句话："串行阶段在同一本地分支上按顺序提交，每个阶段的提交范围就是它的'栈链接'，早上用户按阶段看 `git log`。"这条应该并进 S4 的轻量版。

## S4. 跨多天项目编排（Orchestrate + orch.ts）

1. **问题**：一个要跑好几天、几十个单元的项目，我一天只想看两次。
2. **pstack 解法**（`PB/orchestrate.md`）
   - 触发："run this whole project""own this migration until it lands"。如果一个 agent 在预算内能做完，就**退回 Autonomous run**（`:3,60`）。
   - 三条主规则：完成通知是队列事件，不是打断；每次派生和恢复都原样带上常设指令；brief 就是产品（`:9-11`）。
   - 角色：
     - 协调者不写代码，只写 brief、清 inbox、做判断；
     - 子协调者每条轨道一个，超过一次清空能处理的量才设；
     - worker 默认在云端，一个 worktree 只有一个写者；
     - 验证者用和 worker 不同的模型家族（`:15-19`）。
   - 存储（`:23-32`）：`preferences.md`（编号常设指令，每次派生原样粘贴；发现自己在重复某条指令，就先追加一行）、`units.tsv`、`ledger.tsv`（以 PR+SHA 为键）、`inbox/`、`gates.md`（问题、选项、**无回答时的默认值**）、`decisions.tsv`、`status.md`（从表格派生，不手写）。每个文件只有一个写者。
   - Brief 模板有九个字段：GOAL/SCOPE/CONTEXT/ACCEPTANCE/VERIFY/TIMEBOX/FORBIDDEN/REPORT/STANDING；字段填不出来就说明还没划好范围（`:38-56`）。
   - 步骤（`:60-66`）：
     1. 框定（可数的谓词；预算用到约 70% 就停止派生，开始落地）；
     2. `orch init`；
     3. 先跑一个试点单元，用它证伪 brief 模板；
     4. 滚动窗口扩展（约 10 个在途，不用阻塞批次）；
     5. 清空 inbox；
     6. 持续落地；
     7. 收尾时每个 agent 都要对到终态行，存储保留作复盘材料。
   - 存活与失败（`:95-100`）：
     - 不用 resume 去探活，只读账本、分支、`gh`；
     - 按失败模式重试：超限缩小范围、网络问题原样重试、工具错误换模型、未知原因重试一次；两次失败就放弃并重新规划；
     - 自己连续多次工具失败时，写终态交接再结束。
   - 升级（`:105-109`）：不可逆操作、产品问题、常设指令和现实矛盾、重新规划后仍是死路，这些**批量**写进 `gates.md` 并**绕开继续**；"要不要继续"永远不问人。
3. **机制**：
   - 子 agent 并行（云端）、多模型验证、`/loop` 唤醒 frontier watcher；
   - 脚本 `orch.ts`/`store.ts`（Bun + commander）：纯文件记账 CLI，"一条命令进、一行出"，**不派生、不等待、不唤醒**（`:15`）。它实现了：
     - `unit add/set/list/counts`、`ledger record/check/summary`（同一个 PR+SHA 覆盖写，查不到返回 NOT-VERIFIED，退出码 2）；
     - `inbox push/drain`（drain 时把目录原子 rename 后重建）；
     - `gate park/list/resolve`、`standing add/show`；
     - `status`（从表格渲染 `status.md`，并和上一次对比，输出三行摘要）；
     - `frontier set`（调用 `gt log`/`gt info` 算出 Graphite 栈前沿，generation+1）。
     - 见 `scripts/orch/orch.ts:270-533`、`store.ts:1244-1590`。
   - 健壮性：
     - 原子写：临时文件 + rename（`store.ts:336-347`）；
     - PID 锁：持有者进程已死就自动接管，`--force` 才能抢锁（`store.ts:368-427`）；
     - `bootstrap.ts` 用 package.json 和 bun.lock 的哈希做安装键，按需执行 `bun install --frozen-lockfile` 后重启自身（`bootstrap.ts:17-62`）；
     - 测试覆盖：幂等 init、陈旧锁、强制抢锁、畸形数据拒绝等（`orch.test.ts:183-580`）。
   - 依赖：Cursor 云端 agent、Cursor Projects（`07-overnight.md:94`）、Graphite `gt`（frontier）。
4. **Claude Code 映射**：
   - 记账 CLI 本身与宿主无关，可以直接跑（需要 bun）；
   - 派生和清空可以用 Agent 后台的完成通知、`orchestration` 技能（Orca 的 worker_done 等待和 DAG）；
   - 用户本机已有 Orca，比自己写 orch 更现成（推测：Orca 的决策门和 DAG 能覆盖 inbox/gates）；
   - frontier 依赖 `gt`，用户没有用 Graphite，需要重写或去掉。
5. **成本**：极高（文档自称"刻意的重型方案"，`07-overnight.md:86`）。加上协调者自身的上下文和每次派生都要粘贴的常设指令。
6. **devflow 现状**：
   - 没有编排器。
   - ludus 的真实形态是：一份计划 → 契约拆分表 → 一次 arm 一份契约（p0、p1-core、p1-web、p1-godot、p1-bench），用户每阶段回来重新 arm。这正是 Orchestrate 要消灭的"每 5 分钟 / 每小时回来一次"，只是规模小两个数量级。
   - `plan-unattended.md` 只覆盖单个完成条件，没有覆盖"一份计划多个阶段"。
7. **判断**：**整体不需要；改写后采用其中四条思想**：
   - (a) 一次运行可以带一串阶段，每阶段有自己的完成条件，前一阶段完成就自动进入下一阶段，同一分支顺序提交；
   - (b) 用 `gates.md` 式的"停放 + 默认值 + 绕开继续"代替收尾；
   - (c) 状态从表格或日志派生，不手写叙述；
   - (d) "能被一个 agent 做完就别上重型机器"这条路由规则。

   orch.ts 不搬。

## S5. 安全暂停（Pause safely）

1. **问题**：我要合电脑、重启，或者上下文快满了，希望 agent 干净地停在一个能续上的点。
2. **pstack 解法**（`PB/pause-safely.md:3-10`）：
   - 只有显式要求才暂停，"keep going / 去睡了"永远不触发暂停；
   - 步骤：
     1. 停在安全边界：完成或撤回当前原子步骤，不开始新步骤，取消嵌套子 agent；
     2. 暂停时不做不可逆操作，不新开 PR，不新推送；
     3. 把未提交改动做成一个 `wip:` 提交，树坏了就在正文写一行；
     4. 把恢复笔记写到上下文之外：意图、进度、已验证项、下一步、关键文件、坑；压缩触发时写到 `/tmp/<slug>-resume.md`；已经有决策日志就指向它，不重复。
   - 触发场景还包括"Cursor 重启""即将压缩"（`SKILL.md` Playbooks 的 Pause safely 条目）。
3. **机制**：纯提示词。
4. **Claude Code 映射**：
   - 用户说"暂停"时直接执行；
   - 压缩触发可以挂 **PreCompact hook**：注入"先写恢复笔记"的提醒，或者直接由 hook 脚本把日志尾部和 `git status` 写进恢复文件（推测：PreCompact 能否让模型先执行一轮需要验证，比较稳的是 hook 脚本自己落盘）；
   - SessionStart（source=compact/resume）hook 可以把恢复笔记注入回上下文（推测）。
5. **成本**：很低。
6. **devflow 现状**：
   - autorun 只有 Abort（用户 Esc 加删标记，`DF/skills/devflow-autorun/SKILL.md:79-83`），没有 wip 提交，也没有恢复笔记；
   - tick 每轮重读日志尾部（tick:21-23），这能部分抵消压缩的影响；
   - `plan-unattended.md` 没有暂停路径，风险段只说"会话被关就靠新会话读日志接手"（`plan-unattended.md:208`）。
   - 和 devflow 规则的冲突："没进展就撤销"和"wip 提交"矛盾，需要定义清楚：暂停时的半成品如果属于未验证的本轮改动，就提交到 `wip:` 并在日志里标出，接手时第一步决定保留还是撤销。
7. **判断**：**改写后采用**。在 unattended.md 加一个"暂停"小节（4 步）。可选加 PreCompact/SessionStart hook。

## S6. 新会话接手（Session pickup）

1. **问题**：会话断了，或者换了一个新会话，希望它接着做，不要从头再验证一遍。
2. **pstack 解法**（`PB/session-pickup.md:3-11`）：
   1. 找到上一段的记录（本工作区的对话记录、云端 URL 或已推的分支），先读概要和最后几条消息；长记录交给子 agent 解析，只把精简时间线留在主线程；不要跨工作区去 glob 对话记录；
   2. 重建运行状态：分支、已落地的提交、todo、已做的决定；"上一段的记录是权威输入"；
   3. 对比已做和待做，确定恢复点，不重跑已做的复现；
   4. 路由到对应剧本；
   5. 在真实产物上核对继承来的结论，不能把"上一段自报通过"当证据。
   - 配套规则：接手时写一行 `start`，注明继承的 ts 范围（`show-me-your-work/SKILL.md:42`）。
3. **机制**：纯提示词，可选一个解析对话记录的子 agent。
4. **Claude Code 映射**：
   - 对话记录在 `~/.claude/projects/<编码后的项目路径>/<session>.jsonl`，可以交给子 agent 解析；
   - 恢复循环：再次 `/loop /devflow-impl 继续无人值守 <slug>`；
   - `claude --resume` 或 `--continue` 也能恢复原会话（推测：恢复后 `/loop` 需要重新启动）。
5. **成本**：低。
6. **devflow 现状**：
   - autorun 的 Resume 段（`devflow-autorun/SKILL.md:58-68`）已经有：跑 `check.sh` 看分支、HEAD 是否等于最后记录的提交、受保护文件；"把记下的决定当作已定，但完成条件要重跑，不信记录里的通过"；重绑会话；写 start 行。这其实比 pstack 更严格。
   - `plan-unattended.md` 决定 6 只说"新会话接手先写 start 行"，**把 Resume 的核对步骤丢了**。
7. **判断**：**改写后采用**。把 Resume 的三项核对（当前分支是 `auto/<slug>`、HEAD 等于日志里最后一个 `commit <sha>`、重跑完成条件）作为提示词保留在 unattended.md。不需要 check.sh，三条 git 命令就够。

## S7. 决策日志与早上审计（show-me-your-work）

1. **问题**：我回来后不想重看一整夜的对话，只想快速判断哪些决定值得怀疑。
2. **pstack 解法**（`PS/skills/show-me-your-work/SKILL.md`）：
   - 格式：TSV 六列 `ts phase decision why evidence result`；证据只写指针（SHA、PR、file:line、产物路径），不写段落（`:13-22`）；
   - `log.sh`：自动打 ts，首次写入时加表头，去掉制表符和换行，以 `= + - @` 开头的单元格前面加单引号，防止表格软件把它当公式执行（`scripts/log.sh:21-42`）；
   - 记什么：分叉、单元完成及验证结果、转向或回退及其触发原因、阻塞、修好的门禁；循环模式每轮一行（`:40`）；
   - 一次运行等于一段对话；接手时写 `start` 行（`:42`）；
   - 位置：默认不提交，放在 `decisions.tsv` 或 `.audit/<slug>.tsv`；只有评审者需要它才能信任结果时才提交（`:46-48`）；
   - 只追加，错了就写一行更正（`:52`）；
   - **对照对话记录审计**：每行都要对应真实动作，证据要能打开，漏记的分叉要补上；只追加更正行，不删不改（`:57-63`）；
   - **跨模型审查**：派另一个模型家族的子 agent 读日志和对话记录，标出证据薄弱、验证没有证据、事后看有风险、粗看会漏掉的点；回复末尾加 Attention 段，首行写 `reviewed by <model>`，"No flags"也是合法结果（`:67-74`）；
   - 早上用法：先读 Attention 段，再看它指向的那几行（`07-overnight.md:62-68`）。
3. **机制**：
   - 脚本 `log.sh`：追加一行 TSV，并做转义；
   - 多模型：Cursor 的 Task 指定模型；
   - 对话记录目录 `agent-transcripts/` 属于 Cursor 特性。
4. **Claude Code 映射**：
   - `log.sh` 直接可用（devflow 已经搬过来）；
   - 跨模型审查用 `codex exec -s read-only`（本机 codex-cli 0.162.1）；
   - 对话记录可以在 `~/.claude/projects/...jsonl` 找到，但很大，建议先让 Claude 子 agent 把它压成时间线，再交给 codex（推测：直接塞 jsonl 给 codex 会很贵）。
5. **成本**：
   - 日志：几乎为零；
   - 审计：一次子 agent 读对话记录，长运行的话较贵；
   - codex 审查：一次。
6. **devflow 现状**：
   - `log.sh` 已搬（`DF/skills/devflow-autorun/scripts/log.sh`），每轮一行，有 close 行，日志对照 `git log` 核对（tick:68-69）；
   - 没有对照对话记录的审计，也没有跨模型审查；
   - `plan-unattended.md` 决定 8.5 加了 codex 审查，输入是日志、`git log -p` 和完成条件，**没有对话记录**。这样 pstack 列出的"验证步骤跳过，或在对话记录里没有证据"这一类问题就查不到。
7. **判断**：**照搬**（格式、规则、Attention 段）。审查输入要补上对话记录的精简时间线。

## S8. 自定义长流程（figure-it-out）

1. **问题**：任务很大（迁移、跨模块改动），没有现成的流程，我又要离开后再回来审。
2. **pstack 解法**（`PS/skills/figure-it-out/SKILL.md:9-52`）：先交付"工作流本身"，再写代码。
   - A 框定：可证伪的完成谓词、量化的范围、严格程度（偏高）；长跑之前给一次检查点；
   - B 设计：拆成能独立落地的原子单元，风险最大的未知先做；验证框架先于功能，并捕获改动前的基线；单向门才做设计竞赛；只沿接缝并行，每个 worker 独立 worktree；
   - C 循环：每个单元是一次实验（假设 → 最小改动 → 在真实产物上测 → 保留或回退）；裁决只有三种：VERIFIED、NOT VERIFIED、INCONCLUSIVE，后者不算通过；worker 刷门禁就重置并加固契约；
   - D 日志：走 show-me-your-work，通常要提交；
   - E 收尾：对照 A 的谓词在真实产品上核对，把反复出现的纠正固化成门禁或脚本。
   - 过夜任务会被路由到这里（`07-overnight.md:38`）。
3. **机制**：纯提示词，可选 arena/architect（多模型）。
4. **Claude Code 映射**：可以实现，它就是 devflow-plan 加 devflow-impl 的组合。
5. **成本**：中。设计阶段多一次框定；设计竞赛部分很贵，可以跳过。
6. **devflow 现状**：devflow-plan 已经覆盖框定、拆分、验收标签和契约拆分表；devflow-impl 覆盖分阶段执行。缺的是"验证框架和基线先于功能"的显式要求，以及 INCONCLUSIVE 不算通过。
7. **判断**：**不需要单独技能**。把"先捕获基线、INCONCLUSIVE 不算通过"两句并进 devflow-plan/impl 即可。arm 时已经要求条件"现在失败、记录基线"，这部分已经有了。

## S9. 事件触发的自动化（benny）

1. **问题**：Slack 里有人报 bug，希望自动分诊、复现，并在有证据时开草稿 PR，不需要我去启动。
2. **pstack 解法**（`PS/automations/benny/`）：
   - 两个 Cursor Automation 通过 Slack 线程里的**标记**串联：
     - 分诊只发一条回复，以 `[benny:bug|performance|other]` 结尾（`triage-issue-reports/SKILL.md:200-224`）；
     - 复现自动化等待"指定身份 + 同一线程 + 恰好一个标记"，才继续（`reproduce-and-fix-issues/SKILL.md:56-78`）。
   - 硬规则：
     - 冻结来源坐标，每次发帖前做预检，永不发根消息（`triage:15-28,30-42`）；
     - 只有协调者能发 Slack，子 agent 只读、拿不到凭证；隔离无法保证时由协调者自己做（`repro:17-23`）；
     - 有人认领修复就停，已有 PR 或提交就切到验证模式（`repro:80-103`）；
     - 真实 UI 上复现两次，状态检查不能注入症状（`repro:25-27,163-183`）；
     - 媒体审阅者独立确认证据（`repro:194-196`）；
     - 拒绝窗口过后才进入修复（`repro:216`）；
     - 修复要满足七项门槛（`repro:228-238`）；
     - 编译、单测、看起来合理的 diff 都不算修复后的证据（`repro:280`）；
     - 只开草稿 PR，不合并（`FOR_AGENTS.md:36`）；
     - 建了工单但发帖失败就做补偿（`triage:228`）；
     - 缺任何配置就失败关闭（`FOR_AGENTS.md:35`）。
   - 通用原则：每个阶段都能叫停流水线，每个阶段都交接证据（`07-overnight.md:111-114`）。
3. **机制**：依赖 Cursor 特性，即 Automations（Slack 新消息触发、`/automate` 创建、Automations 编辑器）、Cursor 的 Slack actions、`.cursor/settings.json` 的项目级插件、`control-ui` 适配器。只有 setup 的配置合并属于脚本工作。
4. **Claude Code 映射**：
   - 推测可行，但需要另外搭：GitHub 事件可以用 `anthropics/claude-code-action`（issue 或评论触发）；定时触发可以用 `schedule` 技能（云端 routine）；Slack 方向有 Claude in Slack（Claude Tag）；
   - 本地常驻可以用 CronCreate 或 `/loop 30m` 轮询，但要求会话一直开着；
   - 多阶段用"标记"串联这个设计可以照搬（例如 issue 标签或评论标记）。
5. **成本**：
   - 搭建：高（触发器、凭证隔离、控制适配器、feature map）；
   - 运行：每份报告一到两个 agent 会话，加上 UI 复现录屏。
6. **devflow 现状**：没有对应物。devflow-debug 是人触发的单次调试。
7. **判断**：**不需要**（现阶段）。用户的痛点是"自己发起的长任务老是停"，不是"没人启动"。只值得记住两条原则："每个阶段都能叫停，每个阶段都交接证据"，以及"阶段之间用可机器判定的标记交接，不靠自由文本匹配"。

## S10. 横切原则（四条）

| 原则 | 要点（引用） | Claude Code 上的落点 | devflow 状态 | 判断 |
|---|---|---|---|---|
| never-block-on-the-human | 先做后报；可撤销的直接做；不可逆的要确认；产品方向来自人，执行不阻塞（`principle-never-block-on-the-human/SKILL.md:9-15`） | 提示词 | autorun 遇到用户决定就停放，全停放就收尾，等于事实上在阻塞人 | **改写后采用**：要和用户的"提交/推送前确认"规则并存，所以授权只在框定时一次性给出，只覆盖本分支的本地提交 |
| guard-the-context-window | 按阶段控制规模，把大块内容交给子 agent，主线程只留摘要（`principle-guard-the-context-window/SKILL.md:9-12`；本地副本只有一条 Pattern） | 测试输出重定向到文件，日志证据写成指针；长对话记录交给子 agent 压缩 | tick 每轮重读日志尾部 | **照搬**：在 unattended.md 加一句"大输出写文件，日志里只放路径" |
| make-operations-idempotent | 运行两次结果一样；上一次在任意位置崩溃，重跑也能收敛到同一终态；收敛式启动；PID 陈旧锁（`principle-make-operations-idempotent/SKILL.md:9-24`；`orch` 的锁实现在 `store.ts:368-427`） | 每轮开头先做收敛：未提交改动只可能来自上一轮崩溃，按规则处理 | arm.sh 失败时会撤掉标记；tick 没有定义"开轮时发现脏树怎么办"（check.sh 直接报问题、停止） | **改写后采用**：这是"新方案每轮开头"缺的一步 |
| separate-before-serializing-shared-state | 先消除共享写对象，确实需要共享时再用结构化手段串行；"指令和约定不是并发控制"（`principle-separate-before-serializing-shared-state/SKILL.md:9-16`） | 每个运行一个分支和一个日志文件；不同时在同一工作区跑两个运行 | 已有（`.devflow/<slug>.*` 分开） | **照搬**（已基本满足） |

---

## 本组总结

### 最值得采用的 3 点

1. **"卡住不收尾"的整套规则**：瓶颈期换思路（`autonomous-run.md:11`）；人的问题写进 gates，带默认值，绕开继续（`orchestrate.md:30,105-107`）；能实验就不问人（`SKILL.md` Non-negotiables）；"要不要继续"永远不问（`orchestrate.md:107`）。这是"每小时回来一次"的直接解药，比任何守卫都对症。
2. **决策日志 + 对照审计 + 跨模型 Attention 段**（show-me-your-work）：早上只看 Attention 和它指向的行。devflow 已经有日志，补上"对话记录时间线作为审查输入"和 Attention 格式即可。
3. **"每轮一个最小改动、验证、提交或丢弃"加上"唤醒机制二分"**（`autonomous-run.md:5-9`）：没有事件时用 `/loop` 心跳，有事件时用后台 Bash 或 Monitor 等事件。再加上"运行可以带一串阶段"（从 Orchestrate 里借来的最小部分），覆盖 ludus 的多契约用法。

### 最不值得采用的 3 点

1. **Autopilot-full / Autopilot-stack**：每 PR 一个云端 owner，swarm 多路验证，agent 自己合并或 force-push。与用户的推送/提交确认规则冲突，成本是 N×6 个 agent，ludus 没有这种需求。
2. **Orchestrate 的完整机器和 orch.ts**：Bun 记账 CLI、Graphite frontier、子协调者、滚动窗口、每次派生粘贴常设指令。为"几十到几百个子 agent"设计，文档自己也说是刻意的重型方案。
3. **benny 事件自动化**：深度依赖 Cursor Automations、Slack actions 和 UI 控制适配器，用户当前的痛点也不在"没人启动"。

### 对 `docs/plan-unattended.md` 的具体修改建议

按方案原有结构，逐条给出：

1. **§2.1 来源更正**：
   - "只有用户能做的决定：在完全授权下，先按默认做"在 autonomous-run 里没有原文。autonomous-run 只说"surface"（`autonomous-run.md:9`）。最接近的出处是 Orchestrate 的 `gates.md`（问题、选项、无回答时的默认值）和"停放后绕开继续"（`orchestrate.md:30,105`）。建议改写出处，避免日后误以为 autonomous-run 有这条。
   - 补一句：pstack 还有"先赢得信任再开循环"（`07-overnight.md:9-16`）和"时长不是完成条件"（`:118`）。
2. **决定 5 改为"先绕开，再默认"**：遇到只有用户能定的问题，先在日志里写 `gate` 行（问题、选项、默认值、理由），然后**优先做不依赖它的单元**。只有在没有独立单元可做时，才按默认推进，而且按默认做的工作要单独提交（提交信息标 `default:`），方便早上整段 revert。直接在默认值上越叠越多，是这条规则最大的风险，§7 第三条风险已经点到，但没有给出缓解办法。
3. **决定 3.5 的停止条件放宽，并改为按单元判断**：
   - "连续 3 轮无进展且换过一次思路"对某个**单元**生效：把这个单元标为死路并记录，然后换别的单元；
   - 只有当所有剩余单元都是死路或 gate 时，运行才停；
   - 对齐 pstack 的逃生口"truly stuck after a few hours"（`07-overnight.md:26`），加一个最短时长，例如死路判定至少要两次不同思路，且耗时超过 30 分钟。
   - 理由：ludus 的 p1-bench 15–90 分钟一停，正是这条规则太紧加上全停放就收尾造成的。
4. **新增"多阶段运行"**（建议作为决定 3 的扩展）：完成条件可以是有序的阶段列表 S1..Sn（直接取自批准计划的阶段，每阶段有自己的命令型条件）。阶段完成就记一行 `stage-done`，然后进入下一阶段，同一 `auto/<slug>` 分支顺序提交。某阶段卡在 gate 上时，如果后续阶段不依赖它就继续往后做。验收 E1 应该用 ludus 的多阶段计划来测"用户介入次数"。
5. **决定 2 补"唤醒方式"**：
   - 默认用 `/loop`（动态）；
   - 如果某一步要等长时间的外部结果（长构建、长 benchmark、CI），用后台 Bash（退出时唤醒）或 Monitor 等事件，不在循环里 sleep 轮询；
   - 一次只挂一个等待者（`babysit.md:12`）。
6. **决定 2 补"首次运行建议"和"拒收时长型条件"**：
   - 新类型任务的第一次运行，建议用户看前几轮。原 autorun 已有这条（`devflow-autorun/SKILL.md:42`），方案把它丢了；
   - 用户只给时长（"跑 4 小时"）时，框定必须要求补一个能判对错的条件。
7. **决定 3 补"途中发现"**（`autonomous-run.md:9`）：
   - 和完成条件相关的工具故障、不稳定的检查、明显的相关 bug，可以在写入范围内用单独提交修，并记一行；
   - 范围外的写进收尾的"后续事项"，不顺手改；
   - 这条要和"不改完成条件用到的测试/脚本"区分清楚：不稳定的检查脚本属于受保护路径，只能停放，不能修。
8. **决定 3 每轮开头加收敛步骤**（idempotent）：
   - 读日志尾部后，看 `git status`；
   - 如果有未提交改动，说明是上一轮中断留下的。最后一行日志是"进行中"就重跑检查，按进展/无进展处理；否则撤销；
   - 都要记一行；
   - 同时核对 HEAD 等于日志里最后一个 `commit <sha>`，不等就停下报告。这是 check.sh 最有价值的一条，用一条 git 命令就能保留。
9. **新增"暂停"小节**（pause-safely）：
   - 用户说"暂停/先停一下/我要重启"时：完成或撤回当前步骤；未提交改动做成 `wip:` 提交并记一行；写恢复点（直接用日志的最后一行 `pause`：当前单元、下一步、坑）；停止循环；
   - "去睡了/别停"永远不触发暂停；
   - 可选：PreCompact hook 把 `git status` 和日志尾部落盘（推测，需要验证）。
10. **决定 6 恢复"接手核对"**：新会话说"继续无人值守 <slug>"时：
    1. 确认当前分支是 `auto/<slug>`；
    2. HEAD 等于最后记录的提交；
    3. 重跑全部完成条件，不信日志里的通过；
    4. 写 `start` 行，注明继承的 ts 范围；
    5. 再启动 `/loop`。

    这几步原来在 `devflow-autorun/SKILL.md:58-68`，删 autorun 前必须先迁到 unattended.md。
11. **决定 8.5 审查输入补对话记录**：
    - 先让一个 Claude 子 agent 把本会话 jsonl（`~/.claude/projects/...`）压成"时间 + 动作 + 验证命令和结果"的时间线文件，再连同日志、`git log -p` 和完成条件一起交给 `codex exec -s read-only`；
    - 否则查不到"声称验证但对话记录里没跑"这类问题（`show-me-your-work/SKILL.md:69-72`）。
    - 收尾前还应该自己做一遍"日志对照对话记录"（`:57-63`），不只对照 `git log`。
12. **决定 8 收尾加一条结构化检测**（替代守卫）：`git diff --name-only <基线>..HEAD` 必须不含完成条件用到的测试、样本、脚本，并检查本地远端引用没有变化。把这条结果写进收尾回复。守卫在 12 次运行里没拦过任何东西，所以在收尾时**检测**比在运行中**拦截**便宜得多，也覆盖了 §7 第一条风险的事后发现。
13. **可选的结构性兜底：Stop hook**（风险段补一条备选）：用 Stop hook 在模型想结束回合时检查"运行标记存在、完成条件未通过、没有 close 行"，满足就阻止结束，并提示"继续或写死路说明"。这直接针对"过早收尾"，和 PreToolUse 守卫是两回事。是否采用由用户定，需要先实测它和 `/loop` 的交互，并加次数上限防止死循环（推测）。
14. **验收补充**：
    - A3 之外加一项：demo 里设置一个"只有用户能定"的问题和一个与它独立的单元，验证运行先做独立单元，没有在默认值上叠加；
    - 再加一项：中途杀掉会话，新会话按第 10 条接手，不重做已提交的单元；
    - E1 记录"用户介入次数 / 阶段数"，与 2.2 节的"约每小时一次"对比。
