#!/usr/bin/env bash
# Put this machine's ~/.claude into the shape the Herdr agent-spawning setup expects.
#
# What it does:      copies the files in ./claude/ into ~/.claude/, backing up anything it
#                    would overwrite, and drops herdr's config.toml if that machine has none.
# What it will not do: install Herdr (no verified install source — see the skill), and never
#                    rewrite ~/.claude/settings.json. That file is a merge, and an installer
#                    that overwrites it silently discards whatever else the machine had in it.
#                    Unmerged keys are printed at the end instead.
#
#   bash install.sh [--dry-run] [--force] [--claude-dir <path>]
#
#     --dry-run          print every action, change nothing
#     --force            overwrite without keeping a .bak (default keeps one, once)
#     --claude-dir <p>   install into <p> instead of ~/.claude; for testing the copy path
#                        against a scratch directory without touching the real one
#
# Re-running is safe: identical files are skipped, so a second run is a no-op.

set -u

SELF="setup-herdr"
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${HOME}/.claude"
dry=no
force=no
changed=0
skipped=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    dry=yes; shift ;;
    --force)      force=yes; shift ;;
    --claude-dir) DEST="${2-}"; shift 2 ;;
    *) printf '%s: unknown option %s\n' "$SELF" "$1" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
act()  { if [ "$dry" = yes ]; then printf '  would %s\n' "$*"; else printf '  %s\n' "$*"; fi; }
warn() { printf '%s: %s\n' "$SELF" "$*" >&2; }

[ -d "$SRC/claude" ] || { warn "payload missing: $SRC/claude"; exit 1; }

# --- Herdr itself -----------------------------------------------------------------------
# Checked, never installed. Nothing below depends on Herdr running, but all of it is inert
# without it: the hook stands down when HERDR_ENV != 1 and the spawner refuses to run.
if command -v herdr >/dev/null 2>&1; then
  say "herdr: $(herdr --version 2>/dev/null || echo 'present, version unknown')"
else
  warn "herdr is NOT on PATH. Install it first — see claude/skills/setup-herdr/SKILL.md; this script does"
  warn "not install it, because no install source has been verified for this repo."
  warn "Continuing: the Claude Code files below are safe to place now and stay inert."
fi

# --- Files ------------------------------------------------------------------------------
install_file() {
  local rel="$1" src="$SRC/claude/$1" dst="$DEST/$1"
  [ -f "$src" ] || { warn "missing from payload: $rel"; return 1; }

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    skipped=$((skipped + 1))
    return 0
  fi

  if [ -f "$dst" ] && [ "$force" = no ]; then
    if [ ! -f "$dst.bak" ]; then
      act "back up $rel -> $rel.bak"
      [ "$dry" = yes ] || cp "$dst" "$dst.bak" || return 1
    else
      act "keep existing $rel.bak (not overwriting a previous backup)"
    fi
  fi

  act "install $rel"
  if [ "$dry" = no ]; then
    mkdir -p "$(dirname "$dst")" || return 1
    cp "$src" "$dst" || return 1
    case "$rel" in *.sh) chmod +x "$dst" ;; esac
  fi
  changed=$((changed + 1))
}

say ""
say "Claude Code files -> $DEST"
install_file "scripts/herdr-spawn.sh"
install_file "hooks/route-agent-to-herdr.sh"
install_file "hooks/json-field.sh"
install_file "skills/herdr-spawn/SKILL.md"
install_file "skills/herdr/SKILL.md"
# Installed too, so /setup-herdr is available on this machine afterwards without the clone.
install_file "skills/setup-herdr/SKILL.md"
install_file "CLAUDE.md"

# The status lines are PowerShell, so they are Windows-only. Everything else is portable.
case "${OS:-}${OSTYPE:-}" in
  *Windows*|*msys*|*cygwin*)
    install_file "statusline.ps1"
    install_file "subagent-statusline.ps1"
    ;;
  *)
    say "  skipping statusline.ps1 / subagent-statusline.ps1 (PowerShell, Windows only)"
    ;;
esac

# --- Herdr's own config -----------------------------------------------------------------
# Only `onboarding = false`, which suppresses the first-run walkthrough. Written only when
# the machine has no config.toml at all — herdr owns this file and may keep more in it.
herdr_cfg=""
case "${OS:-}${OSTYPE:-}" in
  *Windows*|*msys*|*cygwin*) [ -n "${APPDATA:-}" ] && herdr_cfg="$APPDATA/herdr/config.toml" ;;
  *) herdr_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml" ;;
esac

say ""
if [ -z "$herdr_cfg" ]; then
  say "herdr config: skipped (could not determine the config directory on this platform)"
elif [ -f "$herdr_cfg" ]; then
  say "herdr config: already exists, left alone -> $herdr_cfg"
else
  act "write $herdr_cfg"
  if [ "$dry" = no ]; then
    mkdir -p "$(dirname "$herdr_cfg")" && cp "$SRC/herdr/config.toml" "$herdr_cfg"
  fi
fi

# --- What is left for a human ------------------------------------------------------------
say ""
say "Installed: $changed file(s); already current: $skipped"
say ""
say "Two steps remain, neither of which this script will do:"
say ""
say "  1. herdr integration install claude"
say "     Installs ~/.claude/hooks/herdr-agent-state.ps1 and its SessionStart hook. That file"
say "     is managed by herdr and is overwritten on every integration update, so it is not"
say "     copied from this payload."
say ""
say "  2. Merge settings-fragment.json into ~/.claude/settings.json,"
say "     replacing <HOME> with: $HOME"
say "     It adds the PreToolUse(Agent) hook and the two status lines. Merge, do not replace:"
say "     that file also holds this machine's theme, permissions and auto-mode settings."
say ""
say "Then restart Claude Code — hooks and CLAUDE.md are read at session start."
