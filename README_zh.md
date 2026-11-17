# local-publish-github · GitHub 发布

> 构建于 **dsh-go** 原生插件框架 · 版本 **v0.11.6** · MIT

<p align="center">🌐 <a href="README.md">English</a> · <strong>中文</strong></p>

给 dsh-go 手机 App 用的本地插件：在输入框上方加「发布 GitHub / 存令牌」胶囊，用一条通用命令把**任意项目**发到 GitHub。

确认版本 → 预检 → 隐私扫描 → 附件+SHA256 → 推送（只快进）→ tag（只建不移）→ Release（中文为主）→ 上传 → 回读校验。

<a id="about"></a>

## 关于

```text
确认版本 + 更新说明
  → 预检（令牌 / 仓库 / tag / 远端分支）
  → 隐私与密钥扫描
  → 收集附件 + 生成 SHA256SUMS
  → 提交 → 推送（只允许快进）
  → 建 tag（只建不移）
  → 建 Release（中文说明为主）
  → 上传附件 → 回读校验数量与大小
```

**为什么做这个**

- 手机上发版最怕两件事：**推错仓库**、**tag 被挪走**
- AI 助手容易"没确认就发布"——所以流程里写死两道闸
- 附件传一半失败很常见，需要能续传/覆盖重传

### 一览

| 版本 | 组件 | 依赖 | 许可 |
|---:|---|---|---|
| v0.11.6 | 2 胶囊 + 2 面板 | GitHub REST API、curl、git | MIT |

<a id="features"></a>

## 功能

| 位置 | 名称 | 作用 |
|---|---|---|
| 胶囊 | **发布 GitHub** | 往输入框插入通用发布指令（**不自动发送、不自动发布**） |
| 胶囊 | **存令牌** | 读剪贴板里的令牌，验证后存到 `~/.config/dsh-go/github-token`（0600） |
| 面板 | **GitHub 令牌** | 查看状态 / 删除本机令牌 |
| 面板 | **发布步骤** | 当前发布状态 + 通用流程 + 复制指令 |

<a id="install"></a>

## 安装

```bash
# 从本地目录安装
dsh plugin --profile web add /path/to/local-publish-github

# 或解压 zip 后指向目录
unzip local-publish-github-0.11.6.zip -d local-publish-github
dsh plugin --profile web add ./local-publish-github
```

装完在 App「设置 → 插件」能看到「**GitHub 发布**」；改代码后需**重启内核**重载。

<a id="quickstart"></a>

## 快速开始

1. **建令牌**：GitHub → Settings → Developer settings → Tokens (classic) → 勾 `repo` → 生成
2. **存令牌**：点「存令牌」胶囊（或手动写 `~/.config/dsh-go/github-token`，权限 600）
3. **项目配置（可选）**：`.publish.json`

```json
{
  "repo": "owner/name",
  "display_name": "项目名",
  "assets": ["dist/pkg-v{version}.zip"],
  "notes_file": "CHANGELOG.md"
}
```

4. **先确认**：把「版本号 + 本版更新」发给负责人，得到明确同意
5. **发布**：

```bash
bash bin/publish.sh --dir <项目目录> --version 0.1.0 --notes-reviewed --confirmed
```

<a id="usage"></a>

## 用法示例

```bash
# 只预检，不提交/不推送/不上传
bash bin/publish.sh --dir ./myproj --version 0.2.0 --dry-run

# 发草稿版（先存草稿，人工再点发布）
bash bin/publish.sh --dir ./myproj --version 0.2.0 --draft --confirmed

# 带附件 + 自动生成英文变更附录（中文仍在正文最前）
bash bin/publish.sh --dir ./myproj --version 0.2.0 \
  --assets "dist/*.zip" --generate-notes --confirmed

# 失败重跑（Release 已存在但附件为空时复用）
bash bin/publish.sh --dir ./myproj --version 0.2.0 --resume --confirmed
```

<a id="params"></a>

## 参数

| 参数 | 说明 |
|---|---|
| `--dir` | 项目目录（必填） |
| `--version` | 版本号（必填，**由人决定，脚本不自动升**） |
| `--repo` | `owner/name`（或用 `.publish.json`） |
| `--display-name` | Release 标题用的项目名 |
| `--assets` | 附件，支持 `{version}` 与通配，按行/引号读取 |
| `--notes` / `--notes-file` | 更新说明（默认读 CHANGELOG） |
| `--tag-prefix` | tag 前缀，默认 `v` |
| `--create-repo` / `--public` | 仓库不存在时创建（默认私有） |
| `--dry-run` | 只预检 |
| `--notes-reviewed` | **必填（发布时）**：发布公告已给用户审核原文 |
> **发布公告硬门**：真正发布（非 `--dry-run`）必须同时带 `--notes-reviewed`。
> 意思是「这份公告原文已经给用户看过并同意」——脚本会拒绝没有该参数的发布，防止未经审核直接发。

| `--confirmed` | 用户已确认版本号与内容，允许真正发布 |
| `--draft` / `--prerelease` | 草稿 / 预发布 |
| `--generate-notes` | 附加 GitHub 自动生成的英文变更汇总 |
| `--resume` / `--overwrite-files` | 续传 / 删除本 Release 旧附件后重传 |
| `--allow-overwrite` | 远端有本地没有的提交时才允许覆盖 |
| `--json` | 结束输出机器可读结果 |

<a id="security"></a>

## 安全行为（护栏）

- 令牌必须 **600**，且通过 `curl --config -` 传入，**不进命令行参数**
- 认证失败 / 仓库不存在 / **tag 已存在** / 远端有本地没有的提交 → **直接拒绝**
- tag **只创建，绝不移动**；分支**只允许快进**
- 发布前扫描私钥 / GitHub 令牌
- 发布后**核对附件数量与大小**，不一致即失败
- Release 正文：**中文为主**，英文自动汇总只作附录
- **任何版本号都由人决定**，脚本不自动修改

> ⚠️ **安全提示**：安装任何 dsh-go 插件 = 在你的机器上运行第三方代码，权限与你本人相同。
> 请只用可信来源，尽量锁定 tag/commit，并校验包的 SHA256。

<a id="layout"></a>

## 目录

```text
local-publish-github/
├── package.json         # 插件清单（dshGo 贡献点）
├── cordis.patch.yml     # 注册到 profile
├── lib/index.js         # 胶囊 + 面板
├── bin/publish.sh       # 通用发布脚本
├── docs/
│   ├── 通用发布步骤.md
│   └── .publish.json.example
├── README.md
└── LICENSE
```

<a id="docs"></a>

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/通用发布步骤.md`](docs/通用发布步骤.md) | 通用发布流程：建令牌 → 配置 → 确认 → 发布 → 校验 → 常见问题 |
| [`docs/.publish.json.example`](docs/.publish.json.example) | 项目配置示例（repo / 显示名 / 附件 / CHANGELOG） |

<a id="verify"></a>

## 校验

下载发布包后先校验，再解压：

```bash
sha256sum -c local-publish-github-0.11.6.zip.sha256
# 或
sha256sum local-publish-github-0.11.6.zip
```

校验失败 = 下载不完整或被篡改，请重新下载。

<a id="contributing"></a>

## 贡献

欢迎提 issue、补参数、改进文档。

1. Fork 这个仓库
2. `git checkout -b feature/你的想法`
3. 提交改动（`git commit -m 'Add your idea'`）
4. `git push origin feature/你的想法`
5. 开一个 Pull Request

**注意**：改动涉及发布流程时，请保持现有护栏（tag 不移、分支只快进、令牌不进 argv、附件必须校验）。

### 贡献者

- [@xiaotianya14](https://github.com/xiaotianya14) — 作者

<a id="stack"></a>

## 技术栈

| 层 | 使用 |
|---|---|
| 插件框架 | dsh-go 原生插件（`dshGo.v1`，胶囊 + 面板） |
| 运行时 | Node.js（ESM）、`lib/index.js` |
| 发布脚本 | Bash + curl + git + Python 3（JSON 处理） |
| 外部接口 | GitHub REST API（`api.github.com` / `uploads.github.com`） |

<a id="thanks"></a>

## 致谢

- **dsh-go**：原生插件框架与手机端运行环境
- [cli/cli](https://github.com/cli/cli)、[goreleaser](https://github.com/goreleaser/goreleaser)、[release-please](https://github.com/googleapis/release-please)：仅借鉴发布流程与参数设计（未复制代码）

<a id="contact"></a>

## 联系方式

- 邮箱：<xiaotianya14@gmail.com>
- QQ 群：**258605008**
- 问题反馈：[GitHub Issues](https://github.com/xiaotianya14/local-publish-github/issues)

<p align="right">(<a href="#about">返回顶部</a>)</p>

<a id="version"></a>

## 版本规则

版本号由项目所有者**手动决定**；本插件与脚本**都不自动升版本**。

<a id="license"></a>

## 许可证

MIT（见 [LICENSE](LICENSE)）。

Copyright (c) 2026 xiaotianya14 · 构建于 dsh-go 原生插件框架
