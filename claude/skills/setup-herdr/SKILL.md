---
name: setup-herdr
description: "Set a machine up to run Claude Code agents as Herdr panes — install the spawner, the redirect hook, the skills and the status lines into ~/.claude, and wire Herdr's own Claude integration. Use when standing up a new machine, or repairing one where the spawner or the Agent redirect has stopped working."
disable-model-invocation: true
---

# Setting a machine up for Herdr-spawned agents

Reproduces, on any machine with this repo cloned, the setup where delegated agents run as
Herdr panes instead of in-process subagents. Everything installs under `~/.claude` and Herdr's
own config directory; nothing is written into the repo.

Four steps. Two you can run; two need the operator, and both are marked.

## 1. Herdr must already be installed — check, do not guess

```bash
herdr --version
```

If that fails, **stop and ask the operator to install Herdr**, then resume. Do not attempt an
install: no install source has been verified for this repo, and inventing a download URL or a
package name is exactly the kind of unverifiable claim that gets things wrong. The operator
knows where their copy came from.

If it succeeds, note the version and carry on. The rest is safe to place even without Herdr —
the hook stands down when `HERDR_ENV != 1` and the spawner refuses to run outside a pane — so
a machine can be prepared before Herdr arrives.

## 2. Copy the files

```bash
bash install.sh --dry-run    # read this first
bash install.sh
```

It installs into `~/.claude`: `scripts/herdr-spawn.sh`, `hooks/route-agent-to-herdr.sh` and its
`json-field.sh` parser, the `herdr-spawn` and `herdr` skills, `CLAUDE.md`, and — on Windows only,
since they are PowerShell — the two status lines. It also writes Herdr's `config.toml` if that
machine has none.

Anything it would overwrite is backed up to `<file>.bak` first, once. Identical files are
skipped, so re-running it is a no-op. It never touches `settings.json`; that is step 4.

## 3. Wire Herdr's Claude integration

```bash
herdr integration install claude
```

This is what makes Herdr recognise a Claude session in a pane and track its `idle` / `working` /
`blocked` state — it installs `~/.claude/hooks/herdr-agent-state.ps1` and the `SessionStart`
hook that calls it. That file carries `HERDR_INTEGRATION_ID=claude` and is overwritten whenever
the integration updates, which is why the payload does not ship a copy: a copied one would be
silently replaced, or worse, silently stale.

## 4. Merge the settings — operator confirms, and never replace the file

`~/.claude/settings.json` also holds that machine's theme, permissions and auto-mode
configuration. **Read it, then add the keys from `settings-fragment.json`,
substituting the machine's real home directory for `<HOME>`.** Show the operator the diff before
writing.

Three keys go in:

| Key | Effect |
|---|---|
| `hooks.PreToolUse` matcher `Agent` | refuses in-process subagents that write or run long, and points at the spawner |
| `statusLine` | line 2 shows the Herdr workspace/tab/pane and the Claude session id |
| `subagentStatusLine` | one row per visible subagent |

Merge into the existing arrays rather than assigning over them — a machine that already has a
`PreToolUse` entry (a project guard, say) must keep it. If `herdr integration install claude`
has already added a `SessionStart` hook, leave it exactly as it is.

The fragment's `_comment` key is documentation; do not copy it into `settings.json`.

## 5. Verify — do not report success without this

Restart Claude Code first: hooks and `CLAUDE.md` are read at session start, so nothing above
takes effect in the session that installed it.

Then, in a new session inside a Herdr pane:

```bash
printf '{"tool_input":{"subagent_type":"general-purpose"}}' | bash ~/.claude/hooks/route-agent-to-herdr.sh; echo "exit=$?"
```

Expect the block message and `exit=2`. Then check the live path — call the `Agent` tool with
`subagent_type: general-purpose` and confirm it is refused, and with `subagent_type: Explore`
and confirm it runs. A hook that is present but unwired fails exactly this test, and it is the
failure this whole setup is most likely to hit.

Finally, spawn one agent and let it answer for itself:

```bash
bash ~/.claude/scripts/herdr-spawn.sh probe --task setup-check \
  --orchestrator <this session's name from ListAgents> \
  --prompt "Reply to <that same name> with SendMessage, reporting your CC_TEAM_* env vars."
```

A reply that carries `CC_TEAM_ORCHESTRATOR` proves the whole chain: pane created, agent named,
env injected, and messaging live in both directions. Then `herdr tab close <tab_id>`.

## What this deliberately does not carry

The `autoMode` block in `settings.json` is per-machine and per-organisation — it is written by
`/auto-mode-setup` against the environment it finds. Do not copy one machine's autoMode onto
another; run `/auto-mode-setup` there instead.
