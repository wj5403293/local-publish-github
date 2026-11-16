// 本地 dsh-go 插件：输入框上方的「发布 GitHub / 存令牌」胶囊。
// 「发布 GitHub」只插入通用发布指令（不自动发送）；真正的发布由
// bin/publish.sh 完成（--dir/--version/--confirmed，支持 --create-repo/--dry-run）。
// 「存令牌」在用户点按时读剪贴板里的 GitHub 令牌，先验证再写入
// ~/.config/dsh-go/github-token（0600）；令牌不回显、不进聊天、不进仓库。
import { promises as fs } from 'node:fs'
import fsSync from 'node:fs'
import { execSync, spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
const PLUGIN_DIR = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
import os from 'node:os'
import path from 'node:path'

export const name = 'local-publish-github'

// classic token（ghp_…/gho_…/ghu_…/ghs_…/ghr_…）与 fine-grained（github_pat_…）。
const TOKEN_RE = /^(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})$/

function tokenFile() {
  const home = process.env.HOME || os.homedir()
  return path.join(home, '.config', 'dsh-go', 'github-token')
}

async function verifyToken(token, signal) {
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort(), 20_000)
  const onAbort = () => ac.abort()
  if (signal) signal.addEventListener('abort', onAbort, { once: true })
  try {
    const res = await fetch('https://api.github.com/user', {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/vnd.github+json',
        'User-Agent': 'dsh-go-local-publish-github',
      },
      signal: ac.signal,
    })
    if (res.status === 401) throw Object.assign(new Error('bad token'), { kind: 'invalid' })
    if (!res.ok) throw Object.assign(new Error(`HTTP ${res.status}`), { kind: 'http' })
    const body = await res.json()
    const login = typeof body?.login === 'string' ? body.login : ''
    if (!login) throw Object.assign(new Error('no login'), { kind: 'http' })
    return login
  } finally {
    clearTimeout(timer)
    if (signal) signal.removeEventListener('abort', onAbort)
  }
}

function tokenStatus() {
  try {
    const raw = fsSync.readFileSync(tokenFile(), 'utf8').trim()
    if (!raw) return { saved: false, tail: '' }
    return { saved: true, tail: raw.slice(-4) }
  } catch {
    return { saved: false, tail: '' }
  }
}

async function saveToken(token) {
  const file = tokenFile()
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 })
  await fs.writeFile(file, `${token}\n`, { mode: 0o600 })
  await fs.chmod(file, 0o600)
  return file
}

export function apply(ctx) {
  ctx.inject(['dshGo'], (ctx) => {
    // 通用发布胶囊：只插入「先确认再发布」的指令，绝不自动发
    const PUBLISH_PROMPT = [
      '【GitHub 发布 · 通用流程】按顺序做，不许跳步、不许自动发布：',
      '1. 找项目目录下的 .publish.json（没有就问我：仓库 owner/name、显示名、附件路径）；',
      '2. 读 CHANGELOG.md 最新一段，整理「本版更新」；',
      '3. 把「版本号 vX.Y.Z + 更新内容」发我确认，我说「确认发布」之前不许发布、不许改版本号；',
      '4. 我确认后执行：bash ' + path.join(PLUGIN_DIR, 'bin', 'publish.sh') + ' --dir <项目目录> --version <V> --confirmed',
      '5. 完成后把 Release 链接、附件列表、sha256 发我。',
      '禁止：跳过第3步、自动升版本、把令牌发进聊天。',
    ].join('\n')
    ctx.dshGo.on('publish-github', () => ({ insert: PUBLISH_PROMPT }))

    ctx.dshGo.on('save-token', (scope) => {
      const raw = typeof scope?.clipboard === 'string' ? scope.clipboard.trim() : ''
      const st = tokenStatus()
      if (!raw) {
        return { toast: st.saved ? `令牌已在（尾号 ${st.tail}），先复制新令牌再点` : '剪贴板是空的，先复制 GitHub 令牌' }
      }
      if (!TOKEN_RE.test(raw)) {
        return { toast: st.saved ? `剪贴板里不是令牌；已存尾号 ${st.tail}` : '剪贴板里不是 GitHub 令牌，先复制令牌' }
      }
      return {
        pending: { label: '验证令牌中', timeoutMs: 45_000 },
        result: async (signal) => {
          let login = ''
          try {
            login = await verifyToken(raw, signal)
          } catch (err) {
            if (signal?.aborted) return { toast: '已取消' }
            if (err?.kind === 'invalid') return { toast: '令牌无效或已过期，重新生成一个' }
            return { toast: '连不上 GitHub，等网络好点再点' }
          }
          try {
            await saveToken(raw)
          } catch {
            return { toast: '令牌有效，但写进本机失败了' }
          }
          const who = login.length > 12 ? `${login.slice(0, 12)}…` : login
          return { toast: `令牌已存好，已验证：${who}` }
        },
      }
    })



    ctx.dshGo.panel('publish-guide', {
      view: () => ({
        type: 'stack',
        title: '发布步骤（通用）',
        children: [
          { type: 'text', text: '适用于任何项目：先把本版做完，再按下面顺序发布。' },
          { type: 'keyValue', items: [
            ['当前状态', { $: 'data.state' }],
            ['本机令牌', { $: 'data.token' }],
            ['项目', { $: 'data.project' }],
          ]},
          { type: 'text', text: '1) 项目里放 .publish.json（repo/显示名/附件）\n2) 更新版本号（人工改）\n3) 写 CHANGELOG 本版更新\n4) 发我确认\n5) 执行 publish.sh --confirmed\n6) 回传 Release 链接与 sha256' },
          { type: 'actions', items: [
            { label: '复制发布指令', action: 'copyPrompt' },
            { label: '刷新状态', action: 'refresh' },
          ]},
        ],
      }),
      data: (scope, emit) => {
        let kv = {}
        try {
          const dir = '/tmp'
          const cands = fsSync.readdirSync(dir).filter((f) => /^gh-publish\..*\.status$/.test(f))
            .map((f) => ({ f, t: fsSync.statSync(path.join(dir, f)).mtimeMs }))
            .sort((a, b) => b.t - a.t)
          if (cands.length) {
            fsSync.readFileSync(path.join(dir, cands[0].f), 'utf8').split('\n').forEach((l) => {
              const i = l.indexOf('='); if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1)
            })
          }
        } catch {}
        const version = kv.VERSION || ''
        const state = kv.STATE === 'running' ? ('发布中：' + (kv.STEP || ''))
          : kv.STATE === 'dry-run' ? ('预检通过（未发布）v' + version)
          : kv.STATE === 'done' ? ('完成 v' + version)
          : kv.STATE === 'fail' ? ('失败：' + (kv.ERROR || ''))
          : '未运行'
        const st = tokenStatus()
        emit({ state, token: st.saved ? ('已存 …' + st.tail) : '未存', project: kv.PROJECT || '' })
        return () => {}
      },
      actions: {
        refresh: () => ({ refresh: true }),
        copyPrompt: () => ({ copy: PUBLISH_PROMPT, toast: '已复制：发布指令（通用）' }),
      },
    })

    ctx.dshGo.panel('token-manager', {
      view: () => ({
        type: 'stack',
        title: 'GitHub 令牌',
        children: [
          { type: 'text', text: '只存令牌：点一次读一次剪贴板，存好就结束。' },
          { type: 'keyValue', items: [['状态', { $: 'data.status' }], ['尾号', { $: 'data.tail' }]] },
          { type: 'actions', items: [{ label: '删除已存令牌', action: 'clear', style: 'plain' }] },
        ],
      }),
      data: (scope, emit) => {
        const st = tokenStatus()
        emit({ status: st.saved ? '已存' : '未存', tail: st.saved ? `…${st.tail}` : '—' })
        return () => {}
      },
      actions: {
        clear: () => {
          try {
            fsSync.unlinkSync(tokenFile())
          } catch {
            return { toast: '本机没有已存的令牌' }
          }
          return { toast: '已删除本机令牌', refresh: true }
        },
      },
    })
  })
}
