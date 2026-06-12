#!/usr/bin/env bash
#
# Daily AI regeneration with auto-rollback.
#   backup -> Claude rewrites DailyShowcase.astro -> build -> deploy (on success) / restore (on fail)
#
# Run from cron, e.g. once a day at 04:00:
#   0 4 * * *  /path/to/seo-landing/scripts/regen.sh >> /path/to/seo-landing/.regen/cron.log 2>&1
#
# Requirements: the `claude` CLI on PATH and logged in, Node/npm installed.
# Optional: set DEPLOY_CMD to your publish step (e.g. "rsync ...", "vercel deploy --prod", "npx wrangler pages deploy dist").
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGET="src/components/DailyShowcase.astro"
STATE=".regen"
BACKUP="$STATE/last-good.astro"
HISTORY="$STATE/history"
PROMPT_FILE="scripts/regen-prompt.md"
TODAY="$(date +%F)"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$HISTORY"
log() { printf '[regen %s] %s\n' "$(date +%FT%T)" "$*"; }

# Prevent overlapping runs (cron firing while a manual run is in flight, etc).
exec 9>"$STATE/.lock"
if command -v flock >/dev/null 2>&1 && ! flock -n 9; then
  log "another run holds the lock — exiting"
  exit 0
fi

# 0) Seed last-good from current file on first run.
[ -f "$BACKUP" ] || cp "$TARGET" "$BACKUP"

# 0b) Stay in sync with origin before regenerating (best-effort, only if tree is clean).
if git rev-parse --git-dir >/dev/null 2>&1 && git diff --quiet && git diff --cached --quiet; then
  git pull --rebase --autostash origin "$(git rev-parse --abbrev-ref HEAD)" >/dev/null 2>&1 \
    && log "synced with origin" || log "git pull skipped/failed (continuing)"
fi

# 1) Snapshot the current (known-good) file before we let the AI touch it.
PRE="$STATE/pre-$STAMP.astro"
cp "$TARGET" "$PRE"
log "snapshot saved -> $PRE"

# 2) Let Claude rewrite the canvas in place.
PROMPT="$(cat "$PROMPT_FILE")
Today's date is: $TODAY
Now rewrite $TARGET."

log "invoking claude..."
if ! claude -p "$PROMPT" \
      --permission-mode acceptEdits \
      --allowedTools "Read,Edit,Write" \
      --strict-mcp-config \
      --add-dir "$ROOT" >"$STATE/claude-$STAMP.log" 2>&1; then
  log "claude invocation failed — restoring pre-snapshot"
  cp "$PRE" "$TARGET"
  exit 1
fi

# 2b) Freeze this edition as an immutable archive page and update the manifest.
SLUG="$(node scripts/archive-edition.mjs 2>>"$STATE/claude-$STAMP.log")" || SLUG=""
[ -n "$SLUG" ] && log "archived edition -> src/editions/$SLUG.astro" || log "WARNING: archive-edition failed"

# 3) Build. If it breaks, roll back to the last KNOWN-GOOD version (not the broken AI output).
log "building..."
if npm run build >"$STATE/build-$STAMP.log" 2>&1; then
  log "build OK"
  cp "$TARGET" "$BACKUP"                       # promote: this is the new known-good
  cp "$TARGET" "$HISTORY/$TODAY.astro"         # keep a per-day archive

  # Push the new edition back to GitHub (best-effort; local dist/ is the live deploy either way).
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git add "$TARGET" src/editions src/data/editions.json
    if git diff --cached --quiet; then
      log "no component change to commit"
    else
      if git commit -m "chore: daily edition for $TODAY" >"$STATE/git-$STAMP.log" 2>&1 \
         && git push origin HEAD >>"$STATE/git-$STAMP.log" 2>&1; then
        log "pushed edition to origin"
      else
        log "git commit/push failed (see git-$STAMP.log)"
      fi
    fi
  fi

  if [ -n "${DEPLOY_CMD:-}" ]; then
    log "deploying: $DEPLOY_CMD"
    if eval "$DEPLOY_CMD" >"$STATE/deploy-$STAMP.log" 2>&1; then
      log "deploy OK"
    else
      log "deploy FAILED — site source is fine, check deploy-$STAMP.log"
      exit 2
    fi
  else
    log "no DEPLOY_CMD set — dist/ is built and ready to publish"
  fi
else
  log "build FAILED — rolling back to last-good and rebuilding"
  cp "$BACKUP" "$TARGET"
  # Undo the archive snapshot + manifest entry created for this failed edition.
  if git rev-parse --git-dir >/dev/null 2>&1; then
    [ -n "$SLUG" ] && git rm -f --quiet "src/editions/$SLUG.astro" 2>/dev/null || rm -f "src/editions/$SLUG.astro" 2>/dev/null
    git checkout -- src/data/editions.json 2>/dev/null || true
  fi
  npm run build >"$STATE/rebuild-$STAMP.log" 2>&1 || log "WARNING: rollback rebuild also failed (check rebuild-$STAMP.log)"
  exit 1
fi

# 4) Trim history (keep last 30 snapshots/pre files).
ls -1t "$STATE"/pre-*.astro 2>/dev/null | tail -n +31 | xargs -r rm -f
log "done — edition for $TODAY is live"
