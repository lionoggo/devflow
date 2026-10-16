# devflow

个人开发流程 Skill。主入口是 `dflow`，在 Claude Code 和 Codex 里都能用（Codex 侧的对应做法见 `skills/dflow/references/hosts.md`）。

| Skill | 用途 | 安装位置 |
|---|---|---|
| dflow | 唯一入口：按目标选流程（调研、排查、方案、审查、实施、验收、影响面、原型、去 AI 腔、无人值守、交接、进展、复盘、报告、发布、调优），可撤销的步骤不停下等人，收尾给证据。只在点名 `/dflow` 或 `$dflow` 时启用 | ~/.agents/skills、~/.claude/skills |
| dflow-report | 报告 | ~/.codex/skills、~/.claude/skills |

`skills/devflow-*` 是已下线的旧流程，源码留作参考，`install.sh` 不再链接它们，也不再需要 autorun 的全局守卫钩子。

## 安装

```sh
./install.sh          # 建立符号链接；已存在的实体目录或指向别处的链接只报告，不覆盖
./install.sh --check  # 只检查
```

本仓库是唯一的修改位置，各工具目录里都是指向这里的符号链接。

## 测试

```sh
./test.sh   # 运行 skills/*/scripts/*-test.sh
```

修改 `scripts/` 下任何脚本后必须运行。

## 注意

- 有无人值守运行正在进行（任何项目里存在 `.dflow/<slug>.lock/`）时，不要修改本仓库：脚本是实时读取的。
- 提交信息：`<type>(<scope>): <subject>`，不超过 72 字符。
