# 单元任务说明 (unit brief)

One brief per unit; a field you cannot fill means the unit is not scoped yet,
so do not dispatch it. Scale it to the unit: a one-command unit collapses to
a paragraph that still names goal, scope, verify, and report. From pstack
`orchestrate` "The brief".

```text
目标     <一句话，不看对话也能执行>
准备     第一条命令：git switch -C <你的分支> <base>（新 worktree 可能从别的 HEAD 拉出；这一步只在还没有任何改动时做）
范围     只能改：<globs>；不能改：<受保护路径和其他单元的路径>；当前目录就是你的 worktree，只在这里提交
上下文   <相关文件>；<依赖单元的报告原文>（你看不到其他单元）
验收     <能判对错的条件，每行一条>
验证     <只跑仓库里已跟踪的检查命令>；跑不了的写明原因，不要假装跑过
时限     约 <n> 分钟；到时交回已有结果
禁止     push、rebase、merge、reset（准备那一步除外）、stash、改其他分支、改范围外文件、改受保护路径
报告     状态、分支、HEAD、实际跑过的命令和输出、偏差、建议的后续；
         决策行：本单元里的分叉、换思路、放弃的做法，每行六列
         （ts phase decision why evidence result），证据指向提交或 path:line
规则     提交信息 <type>(<scope>): <subject>，不超过 72 字符；只提交通过检查的改动
```
