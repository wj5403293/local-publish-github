# Changelog

> 「本版更新」的唯一来源：发布脚本默认读取最新一段作为 Release 正文。

## [0.11.6] - 2026-11-17

**English documentation / 英文文档**

- Added `README.md` (English) — GitHub renders it as the default README, followed by `README_zh.md` (Chinese) with a language switch.
- English release notes in this section so international users can read what changed.
- No functional changes in this release; installer and guards are the same as v0.11.5.

**中文**

- 新增英文版 `README.md`（GitHub 默认展示），中文移到 `README_zh.md`，两版顶部有语言切换。
- 本版更新同时提供英文说明，方便国外用户阅读。
- 本版**无功能变更**，安装方式与安全护栏同 v0.11.5。

## [0.11.5] - 2026-11-17

**首版：通用发布插件**

- 一键发布任意项目：建仓 / 推送 / 打 tag / 建 Release / 传附件 / 生成 SHA256
- 参数化：`--dir` `--repo` `--version` `--assets` `--notes-file`，支持项目内 `.publish.json`（命令行优先）
- 手机原生界面：「发布 GitHub」胶囊（先确认再发）、「发布步骤」面板、「存令牌」胶囊

**安全护栏**

- tag 只创建、绝不移动；分支只允许快进；远端有本地没有的提交默认拒绝
- 令牌必须 600 权限，且通过 stdin 传入，不进命令行参数
- 发布前扫私钥/令牌；发布后核对附件数量与大小，不一致即失败
- Release 正文中文为主；`--generate-notes` 的英文只作附录

**界面**

- 「发布步骤」面板新增「生成更新说明」「更新说明在哪」按钮：不用每次重复解释更新说明流程
- 更新说明固定来源：`CHANGELOG.md`（发布脚本自动取最新一段作为 Release 正文）

**新增参数**

- `--draft` 草稿、`--prerelease` 预发布
- `--overwrite-files` 覆盖重传本 Release 附件、`--resume` 续传
- `--json` 机器可读输出；附件支持通配与 `{version}` 占位

**修复（自测发现并修正）**

- dry-run 不再产生本地提交（只预检）
- 命令行参数优先于 `.publish.json`（此前配置会覆盖命令行）
- 附件 SHA256 清单每次重建，不跨版本累积

**文档**

- `docs/通用发布步骤.md`：建令牌 → 配置 → 确认 → 发布 → 校验 → 常见问题
- `CHANGELOG.md`：更新说明来源（本文件）
- 开源 README：安装 / 用法 / 参数 / 安全 / 贡献 / 联系方式
