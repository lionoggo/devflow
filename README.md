# devflow

个人开发流程 Skill：plan → research / debug → impl → verify → commit，另有无人值守长运行 autorun 和 Codex 专用的 report。

| Skill | 用途 | 安装位置 |
|---|---|---|
| devflow-plan | 需求与方案、验收标准 | ~/.agents/skills、~/.claude/skills |
| devflow-research | 只读调研 | 同上 |
| devflow-debug | 定位问题 | 同上 |
| devflow-impl | 按计划实施 | 同上 |
| devflow-verify | 独立验收 | 同上 |
| devflow-commit | 提交 | 同上 |
| devflow-autorun | 布置、续跑、中止无人值守运行（仅 `/devflow-autorun`） | 同上 |
| devflow-autorun-tick | autorun 的每轮迭代（由 `/loop` 进入） | 同上 |
| devflow-report | 报告 | ~/.codex/skills |

## 安装

```sh
./install.sh          # 建立符号链接；已存在的实体目录或指向别处的链接只报告，不覆盖
./install.sh --check  # 只检查
```

本仓库是唯一的修改位置，各工具目录里都是指向这里的符号链接。Skill 正文和全局钩子使用 `~/.agents/skills/...` 路径，经链接解析到本仓库。

autorun 的守卫需要注册为 Claude Code 全局 PreToolUse 钩子；`install.sh` 只检查，不修改 `~/.claude/settings.json`，缺失时打印要添加的条目。

## 测试

```sh
./test.sh   # guard-test.sh 和 check-test.sh
```

修改 `guard.sh` 或 `check.sh` 后必须运行。

## 注意

- 有 autorun 正在运行（任何项目里存在 `.devflow/*.running`）时，不要修改本仓库：守卫和 check.sh 是实时读取的。
- 提交信息：`<type>(<scope>): <subject>`，不超过 72 字符。
