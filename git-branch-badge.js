// Git Branch Badge — dynamic Cordis plugin restore archive (pkg-5)
// ===============================================================
// Dynamic plugins are process-local: after `dsh web` restarts this plugin
// is gone. To restore it, ask the agent (this file lives beside the
// desktop launcher kit):
//
//   "恢复 git 徽标插件"  or  "restore gitbdg-1 from ~/.dsh/launchers/git-branch-badge.js"
//
// The agent re-runs cordis_define (idPrefix "gitbdg") with the two halves
// below and activates it with cordis_run. Do NOT paste this file into any
// repo: it is only a restore archive.
//
// Behavior: bottom stats band (conversation.composer.dock, order 1) shows
// git:(branch sha) for the current workspace's repo; git:(—) placeholder in
// non-git workspaces; 30s auto refresh; host resolves the workspace path by
// session id from workspaceRegistry, reads .git/HEAD via the fs service
// (worktree + packed-refs + detached HEAD supported).

HOST_HALF = `
return {
  apply(ctx) {
    const fs = ctx.get('fs')
    const sandboxPolicy = ctx.get('sandboxPolicy')
    if (fs === undefined || sandboxPolicy === undefined) return

    async function readGitFile(gitDir, relative) {
      try {
        const target = await fs.resolve(gitDir + '/' + relative)
        return await fs.readText(target)
      } catch (err) {
        return null
      }
    }

    async function resolveWorkspacePath(sessionId) {
      const registry = ctx.get('workspaceRegistry')
      if (registry === undefined || !sessionId) return undefined
      try {
        const workspaces = await registry.list()
        for (const ws of workspaces) {
          if (ws && Array.isArray(ws.sessionIds) && ws.sessionIds.indexOf(sessionId) !== -1) {
            return typeof ws.path === 'string' ? ws.path : undefined
          }
        }
      } catch (err) {
        // fall through to the deployment workspace root
      }
      return undefined
    }

    async function readGitInfo(rootOverride) {
      try {
        // Prefer the session's workspace path; fall back to the
        // deployment workspace root.
        const root = rootOverride || sandboxPolicy.workspaceRoot
        if (!root) return null
        // .git may be a real dir, or (worktree) a file containing "gitdir: <path>"
        let gitDir = root + '/.git'
        let head = await readGitFile(gitDir, 'HEAD')
        if (head === null) {
          const dotGit = await readGitFile(root, '.git')
          if (dotGit === null) return null
          const m = dotGit.match(/gitdir:\\s*(.+)/)
          if (!m) return null
          gitDir = m[1].trim()
          head = await readGitFile(gitDir, 'HEAD')
          if (head === null) return null
        }
        const value = head.trim()
        if (value.startsWith('ref:')) {
          const branch = value.slice(4).trim().replace(/^refs\\/heads\\//, '')
          let sha = await readGitFile(gitDir, 'refs/heads/' + branch)
          if (sha === null) {
            // branch ref may be packed
            const packed = await readGitFile(gitDir, 'packed-refs')
            const pm = packed ? packed.match(new RegExp('^([0-9a-f]{40}) refs/heads/' + branch + '$', 'm')) : null
            sha = pm ? pm[1] : null
          }
          return { branch, sha: sha ? sha.trim().slice(0, 7) : null }
        }
        return { branch: null, sha: value.slice(0, 7) }
      } catch (err) {
        return null
      }
    }

    return harness.handle('git-info', async (args) => {
      const sessionId = args !== null && typeof args === 'object' && typeof args.sessionId === 'string' ? args.sessionId : undefined
      const path = sessionId ? await resolveWorkspacePath(sessionId) : undefined
      return readGitInfo(path)
    })
  },
}
`

CLIENT_HALF = `
return {
  inject: ['timer'],
  apply(ctx) {
    const slots = ctx.get('slots')
    if (slots === undefined) return

    styles.insert(\`
.dsh-git-badge {
  display: block;
  text-align: center;
  max-width: var(--dsh-chat-content-width, 720px);
  width: 100%;
  margin: 0 auto;
  box-sizing: border-box;
  padding: 0 calc(var(--dsh-composer-side-clearance, 16px) + 16px) 4px;
  font-size: 12px;
  line-height: 20px;
  color: var(--dsw-alias-label-tertiary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
\`)

    function GitBadge(props) {
      const [state, setState] = React.useState({ loaded: false, info: null })
      const sessionId = typeof props.sessionId === 'string' ? props.sessionId : null
      React.useEffect(() => {
        let alive = true
        const refresh = () => {
          host.call('git-info', sessionId ? { sessionId } : {}).then((value) => {
            if (!alive) return
            setState({ loaded: true, info: value !== null && typeof value === 'object' ? value : null })
          }).catch(() => {
            if (alive) setState({ loaded: true, info: null })
          })
        }
        refresh()
        const stop = ctx.interval(refresh, 30000)
        return () => {
          alive = false
          if (stop) stop()
        }
      }, [sessionId])
      if (!state.loaded) return null
      const info = state.info
      const branch = info !== null && typeof info === 'object' && typeof info.branch === 'string' ? info.branch : null
      const sha = info !== null && typeof info === 'object' && typeof info.sha === 'string' ? info.sha : null
      if (!branch && !sha) {
        return React.createElement('span', { className: 'dsh-git-badge', title: '当前工作区不是 git 仓库' }, 'git:(\\u2014)')
      }
      const text = branch ? (branch + (sha ? ' ' + sha : '')) : sha
      return React.createElement('span', { className: 'dsh-git-badge', title: '当前 git 分支：' + (branch || 'detached') }, 'git:(' + text + ')')
    }

    return slots.inject('conversation.composer.dock', () => slots.register(
      { name: 'conversation.composer.dock', id: 'git-branch', order: 1 },
      (props) => React.createElement(GitBadge, props),
    ))
  },
}
`
