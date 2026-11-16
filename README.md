# local-publish-github · One-command GitHub releases

> Built on the **dsh-go** native plugin framework · version **v0.11.5** · MIT

<p align="center">🌐 <strong>English</strong> · <a href="README_zh.md">中文</a></p>

A local plugin for the **dsh-go** mobile app: it adds "Publish GitHub / Save token" capsules above the composer, so you can publish **any project** to GitHub with one generic command.

Confirm version → preflight → secret scan → assets + SHA256 → push (fast-forward only) → tag (create only) → Release (Chinese-first notes) → upload → read-back verification.

<a id="about"></a>

## About

```text
confirm version + release notes
  → preflight (token / repo / tag / remote branch)
  → privacy & secret scan
  → collect assets + generate SHA256SUMS
  → commit → push (fast-forward only)
  → create tag (never moved)
  → create Release (Chinese-first body)
  → upload assets → verify count and size
```

**Why**

- The two scariest part of releasing from a phone: **pushing to the wrong repo** and **a tag being moved**
- AI assistants tend to "publish first, ask later" — so two hard gates are built in
- Uploads fail halfway all the time — you need resume / overwrite re-upload

### At a glance

| Version | Components | Dependencies | License |
|---:|---|---|---|
| v0.11.5 | 2 capsules + 2 panels | GitHub REST API, curl, git | MIT |

<a id="features"></a>

## Features

| Where | Name | What it does |
|---|---|---|
| Capsule | **Publish GitHub** | Inserts a generic release instruction into the composer (**never auto-sends, never auto-publishes**) |
| Capsule | **Save token** | Reads a GitHub token from the clipboard, verifies it, stores it at `~/.config/dsh-go/github-token` (0600) |
| Panel | **GitHub token** | Show status / delete the local token |
| Panel | **Publish steps** | Current status + generic flow + copy instruction |

<a id="install"></a>

## Install

```bash
dsh plugin --profile web add /path/to/local-publish-github

# or unzip first
unzip local-publish-github-0.11.5.zip -d local-publish-github
dsh plugin --profile web add ./local-publish-github
```

After install it appears in **Settings → Plugins** as "GitHub 发布". Restart the core after editing the source.

<a id="quickstart"></a>

## Quick start

1. **Create a token**: GitHub → Settings → Developer settings → Tokens (classic) → scope `repo`
2. **Save it**: tap the "Save token" capsule (or write `~/.config/dsh-go/github-token`, mode 600)
3. **Optional project config** — `.publish.json`:

```json
{
  "repo": "owner/name",
  "display_name": "my-project",
  "assets": ["dist/pkg-v{version}.zip"],
  "notes_file": "CHANGELOG.md"
}
```

4. **Confirm first**: send the version + release notes to the owner and get explicit approval
5. **Publish**:

```bash
bash bin/publish.sh --dir <project> --version 0.1.0 --confirmed
```

<a id="usage"></a>

## Usage examples

```bash
# dry run: no commit, no push, no upload
bash bin/publish.sh --dir ./myproj --version 0.2.0 --dry-run

# draft release
bash bin/publish.sh --dir ./myproj --version 0.2.0 --draft --confirmed

# assets + auto-generated English changelog appendix (Chinese body stays first)
bash bin/publish.sh --dir ./myproj --version 0.2.0 \
  --assets "dist/*.zip" --generate-notes --confirmed

# resume after a failed upload (release exists with no assets)
bash bin/publish.sh --dir ./myproj --version 0.2.0 --resume --confirmed
```

<a id="params"></a>

## Parameters

| Flag | Meaning |
|---|---|
| `--dir` | Project directory (required) |
| `--version` | Version (required, **set by a human; never auto-bumped**) |
| `--repo` | `owner/name` (or via `.publish.json`) |
| `--display-name` | Project name used in the Release title |
| `--assets` | Assets; supports `{version}` and globs, read line by line |
| `--notes` / `--notes-file` | Release body (defaults to CHANGELOG) |
| `--tag-prefix` | Tag prefix, default `v` |
| `--create-repo` / `--public` | Create repo if missing (private by default) |
| `--dry-run` | Preflight only |
| `--confirmed` | User approved; actually publish |
| `--draft` / `--prerelease` | Draft / prerelease |
| `--generate-notes` | Append GitHub auto-generated English notes |
| `--resume` / `--overwrite-files` | Resume / delete this release's assets then re-upload |
| `--allow-overwrite` | Allow overwriting when remote has commits not present locally |
| `--json` | Machine-readable output |

<a id="security"></a>

## Safety guards

- Token must be mode **600** and is passed via `curl --config -` (**never in argv**)
- Auth failure / missing repo / **existing tag** / remote commits not present locally → **refuse**
- Tags are **created only, never moved**; branches must be **fast-forward**
- Scans for private keys / GitHub tokens before publishing
- Verifies asset **count and size** after upload
- Release body is Chinese-first; the auto-generated English part is an appendix only
- **Version numbers are always chosen by a human**

> ⚠️ **Security notice**: installing any dsh-go plugin means running third-party code with your permissions.
> Only install from trusted sources, pin tags/commits, and verify SHA256 of downloaded packages.

<a id="layout"></a>

## Layout

```text
local-publish-github/
├── package.json
├── cordis.patch.yml
├── lib/index.js
├── bin/publish.sh
├── docs/
├── README.md        # English
├── README_zh.md     # 中文
├── CHANGELOG.md
└── LICENSE
```

<a id="docs"></a>

## Docs

| Doc | Content |
|---|---|
| [`docs/通用发布步骤.md`](docs/通用发布步骤.md) | Full release flow (Chinese) |
| [`CHANGELOG.md`](CHANGELOG.md) | Source of the "release notes" |

<a id="verify"></a>

## Verify downloads

```bash
sha256sum -c local-publish-github-0.11.5.zip.sha256
```

<a id="contributing"></a>

## Contributing

1. Fork
2. `git checkout -b feature/your-idea`
3. Commit
4. `git push origin feature/your-idea`
5. Open a Pull Request

Keep the existing guards (tags never move, fast-forward only, token never in argv, assets always verified).

<a id="stack"></a>

## Tech stack

| Layer | Used |
|---|---|
| Plugin framework | dsh-go native plugin (`dshGo.v1`, capsules + panels) |
| Runtime | Node.js (ESM), `lib/index.js` |
| Publishing | Bash + curl + git + Python 3 |
| API | GitHub REST API |

<a id="thanks"></a>

## Thanks

- **dsh-go** — native plugin framework
- [cli/cli](https://github.com/cli/cli), [goreleaser](https://github.com/goreleaser/goreleaser), [release-please](https://github.com/googleapis/release-please) — release-flow ideas only, no code copied

<a id="contact"></a>

## Contact

- Email: <xiaotianya14@gmail.com>
- QQ group: **258605008**
- Issues: [GitHub Issues](https://github.com/xiaotianya14/local-publish-github/issues)

<a id="version"></a>

## Versioning

Version numbers are set **manually by the owner**; neither the plugin nor the script bumps them.

<a id="license"></a>

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 xiaotianya14 · built on the dsh-go native plugin framework
