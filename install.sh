#!/bin/bash
# install.sh: make ~/.claude run from this repo (symlinks), with a backup and a one-command rollback.
#   ./install.sh             DRY RUN (default): what would change, with a diff per file. Changes nothing.
#   ./install.sh --apply     back up every file it replaces, then symlink each managed file into this repo.
#   ./install.sh --rollback  restore the latest backup exactly (files that didn't exist before are removed).
#   ./install.sh --status    check every managed path still links into this repo (catches drift).
# Only the files listed in managed() are touched. Session state (hooks/.state, projects/, memory, transcripts) and
# app-synced skills are never touched. CLAUDE_HOME overrides ~/.claude (tests use it).
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
CH=${CLAUDE_HOME:-$HOME/.claude}
BK=${INSTALL_BACKUPS:-$(dirname "$CH")/.claude-backups}
mode=${1:-dry}

managed() {  # every file under claude/ except docs, app-synced skills and session state
  (cd "$REPO/claude" && find . -type f ! -path './designs/*' ! -path './skills/synced/*' ! -path '*/.state/*' \
     ! -name '.DS_Store' | sed 's#^\./##' | sort)
}

state() {  # state TARGET SOURCE -> linked|file|link-elsewhere|missing
  if [ -L "$1" ]; then [ "$(readlink "$1")" = "$2" ] && echo linked || echo link-elsewhere
  elif [ -e "$1" ]; then echo file; else echo missing; fi
}

version_check() {  # Claude Code < 2.1.290 could skip the settings permission prompt for edits behind a symlinked
  # settings.json (fixed in 2.1.290 per the changelog, read 2026-10-09). Symlinks are only safe from there on.
  local v; v=$(claude --version 2>/dev/null | awk '{print $1}')
  [ -n "$v" ] || { echo "WARNING: claude not found on PATH; can't check its version."; return 0; }
  if [ "$(printf '%s\n%s\n' "$v" 2.1.290 | sort -V | head -1)" != 2.1.290 ]; then
    echo "WARNING: Claude Code $v < 2.1.290. Upgrade first (\`claude update\`); older versions mishandle a symlinked settings.json."
    return 1
  fi
}

case "$mode" in
dry|--dry-run)
  echo "DRY RUN: nothing changes. Repo: $REPO  Target: $CH"
  version_check || true
  n=0
  while read -r rel; do
    src="$REPO/claude/$rel"; dst="$CH/$rel"; s=$(state "$dst" "$src")
    case "$s" in
      linked) continue;;
      missing) echo "+ NEW   $rel";;
      file|link-elsewhere)
        if cmp -s "$dst" "$src"; then echo "= SAME  $rel (becomes a symlink, content unchanged)"
        else echo "~ DIFF  $rel"; diff -u "$dst" "$src" | sed '1,2d' | sed 's/^/    /' || true; fi;;
    esac
    n=$((n + 1))
  done < <(managed)
  echo "$n path(s) would change. Apply with: $0 --apply   (rollback: $0 --rollback)";;

--apply)
  version_check || [ "${INSTALL_ANY_VERSION:-0}" = 1 ] || { echo "Refusing to apply. Upgrade, or set INSTALL_ANY_VERSION=1."; exit 1; }
  # A zero-padded sequence number first, so backups always sort in the order they were made (two applies in the
  # same second used to sort by PID, which could reverse them).
  mkdir -p "$BK"; seq_n=$(( $(find "$BK" -mindepth 1 -maxdepth 1 -type d | wc -l) + 1 ))
  ts=$(printf '%04d' "$seq_n")-$(date +%Y%m%d-%H%M%S); dest="$BK/$ts"; mkdir -p "$dest"
  : > "$dest/manifest"
  while read -r rel; do
    dst="$CH/$rel"; s=$(state "$dst" "$REPO/claude/$rel")
    echo "$s $rel" >> "$dest/manifest"
    # Back up what would be lost. A path already linked here holds nothing to lose (its original is in an
    # earlier backup), so it is recorded as "linked" and left alone on rollback.
    if [ "$s" = file ] || [ "$s" = link-elsewhere ]; then
      mkdir -p "$dest/files/$(dirname "$rel")"; cp -P "$dst" "$dest/files/$rel"
    fi
  done < <(managed)
  # settings.json is also kept as a plain copy: some tools rewrite it in place.
  [ -f "$CH/settings.json" ] && cp "$CH/settings.json" "$dest/settings.json.copy"
  echo "Backup: $dest ($(wc -l < "$dest/manifest" | tr -d ' ') paths recorded)"
  while read -r rel; do
    mkdir -p "$CH/$(dirname "$rel")"; ln -sfn "$REPO/claude/$rel" "$CH/$rel"
  done < <(managed)
  # Merge queue state moves out of the script into $MERGE_STATE (copy only; the old files are left in place).
  MS=${MERGE_STATE:-$HOME/.local/state/merge-queue}; OLD=${OLD_MERGE_DIR:-}
  mkdir -p "$MS"
  if [ -n "$OLD" ] && [ ! -f "$MS/queue.txt" ] && [ -f "$OLD/merge_next.sh" ]; then
    awk '/<<LIST/{f=1;next} /^LIST$/{f=0} f' "$OLD/merge_next.sh" > "$MS/queue.txt"
    [ -f "$OLD/verified.txt" ] && cp "$OLD/verified.txt" "$MS/verified.txt"
    echo "Merge queue copied from $OLD to $MS ($(grep -cv '^#' "$MS/queue.txt" || true) active lines)."
  fi
  "$0" --status;;

--rollback)
  # The newest backup not yet used: a used one is renamed *.rolled-back and never picked again.
  last=""
  for d in "$BK"/*/; do                 # globs expand in sorted order; the last unused one wins
    [ -d "$d" ] || continue
    case "$d" in *.rolled-back/) continue;; esac
    last=${d%/}
  done
  [ -n "$last" ] || { echo "No backup left in $BK"; exit 1; }
  while read -r s rel; do
    dst="$CH/$rel"
    case "$s" in
      linked) ;;                              # was already installed before this apply: nothing to restore
      missing) rm -f "$dst";;
      *) rm -f "$dst"; mkdir -p "$(dirname "$dst")"; cp -P "$last/files/$rel" "$dst";;
    esac
  done < "$last/manifest"
  echo "Rolled back to $last"
  mv "$last" "$last.rolled-back";;

--status)
  bad=0
  while read -r rel; do
    s=$(state "$CH/$rel" "$REPO/claude/$rel")
    [ "$s" = linked ] || { echo "DRIFT $s $rel"; bad=1; }
  done < <(managed)
  [ $bad = 0 ] && echo "STATUS OK: every managed path links into $REPO/claude" || { echo "STATUS: drift found (re-run --apply, or --rollback)"; exit 1; };;

*) sed -n '2,8p' "$0"; exit 2;;
esac
