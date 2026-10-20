#!/bin/bash
# install.sh: install the kit into ~/.claude WITHOUT replacing your own setup, with a backup and a one-command rollback.
#   ./install.sh             DRY RUN (default): what would change, with a diff per file. Changes nothing.
#   ./install.sh --apply     back up everything it touches, then install (below).
#   ./install.sh --rollback  restore the latest backup exactly (files that didn't exist before are removed).
#   ./install.sh --status    check the install is intact (links, settings rules and hooks, CLAUDE.md import).
#   --tool codex,opencode,antigravity|all|none   also set up those agent CLIs (with any mode above). Default: each
#            one found on PATH (codex, opencode, agy). Claude Code's part is always installed: the guards live there.
# What --apply does:
#   - links ~/.claude/kit to this repo, and each program file (hooks, lib, roles, agents) to its copy here, so a
#     `git pull` here updates them;
#   - MERGES the kit's settings into your ~/.claude/settings.json (adds deny rules and hooks; removes nothing);
#   - adds one import line to your ~/.claude/CLAUDE.md (your own text stays);
#   - copies guard.conf, lanes.zsh, roles/ and agents/ only where you don't have them: they're yours to edit
#     afterwards, and a file of yours is never replaced;
#   - for each --tool: MERGES the kit's hooks into that tool's hook file (Codex ~/.codex/hooks.json, Antigravity
#     ~/.gemini/config/hooks.json) or links the OpenCode plugin, and gives the tool the kit's rules in its global
#     AGENTS.md (a link if you have none, else a marked block that --apply keeps current). See docs/OTHER-AGENTS.md.
# Session state (hooks/.state, projects/, memory, transcripts) is never touched. CLAUDE_HOME overrides ~/.claude.
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
CH=${CLAUDE_HOME:-$HOME/.claude}
BK=${INSTALL_BACKUPS:-$(dirname "$CH")/.claude-backups}
KIT_SETTINGS=${KIT_SETTINGS:-$REPO/claude/settings.json}
IMPORT='@~/.claude/kit/claude/CLAUDE.md'
TH=$(dirname "$CH")   # the home the other tools' config lives under (a sandbox in the tests)
RULES_SRC=$REPO/claude/CLAUDE.md
mode=dry; TOOLS_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tool|--tools) [ $# -ge 2 ] || { echo "install: --tool needs a value (codex,opencode,antigravity|all|none)"; exit 2; }
      TOOLS_ARG=$2; shift 2;;
    --tool=*|--tools=*) TOOLS_ARG=${1#*=}; shift;;
    *) mode=$1; shift;;
  esac
done
detect_tools() {
  local t=""; command -v codex >/dev/null 2>&1 && t="$t,codex"
  command -v opencode >/dev/null 2>&1 && t="$t,opencode"; command -v agy >/dev/null 2>&1 && t="$t,antigravity"
  echo "${t#,}"
}
TOOLS=""
for t in $(printf '%s' "${TOOLS_ARG:-${KIT_TOOLS-$(detect_tools)}}" | tr ',' ' '); do
  case "$t" in
    all) TOOLS="codex opencode antigravity";;
    none|claude) ;;
    codex|opencode|antigravity) case " $TOOLS " in *" $t "*) ;; *) TOOLS="${TOOLS:+$TOOLS }$t";; esac;;
    *) echo "install: unknown tool '$t' (use codex, opencode, antigravity, all or none)"; exit 2;;
  esac
done
case "$mode" in --rollback|--status) TOOLS=""; [ -f "$CH/kit-tools" ] && TOOLS=$(tr '\n' ' ' < "$CH/kit-tools"); TOOLS=${TOOLS% };; esac

resolve() { case "$1" in @/*) echo "$TH/${1#@/}";; *) echo "$CH/$1";; esac; }   # manifest path -> real path
tool_targets() {  # the files each selected tool gets, relative to your home ("@/")
  local t; for t in $TOOLS; do
    case "$t" in
      codex) echo @/.codex/hooks.json; echo @/.codex/AGENTS.md;;
      opencode) echo @/.config/opencode/plugins/agentic-kit.js; echo @/.config/opencode/AGENTS.md;;
      antigravity) echo @/.gemini/config/hooks.json; echo @/.gemini/AGENTS.md;;
    esac
  done
}
link_src() {  # what a linked tool file points at (empty: a merged file, never a link)
  case "$1" in */AGENTS.md) echo "$RULES_SRC";; */agentic-kit.js) echo "$REPO/tools/opencode/agentic-kit.js";; kit) echo "$REPO";; @/*) ;;
    *) echo "$REPO/claude/$1";; esac
}
render() {  # the tool's hook file with the hooks' folder written out in full, shell-quoted (a home may have spaces)
  local q; q="'$(printf '%s' "$CH/hooks" | sed "s/'/'\\\\''/g")'"
  jq --arg q "$q" 'walk(if type == "string" then gsub("@KIT_HOOKS@"; $q) else . end)' "$REPO/tools/$1/hooks.json"
}
codex_merge() {  # codex_merge merge|check: settings-merge.py on ~/.codex/hooks.json and the rendered kit hooks
  # A real file, not <(...): settings-merge.py reads a zero-size file as {}, and on Linux a pipe has size 0.
  local k rc=0; k=$(mktemp "${TMPDIR:-/tmp}/kit-codex.XXXXXX")
  render codex > "$k"
  python3 "$REPO/bin/settings-merge.py" "$1" "$TH/.codex/hooks.json" "$k" || rc=$?
  rm -f "$k"; return $rc
}
hooks_merged() {  # hooks_merged TOOL: print what that tool's hook file would become
  case "$1" in
    codex) codex_merge merge;;
    antigravity) local f=$TH/.gemini/config/hooks.json
      { if [ -s "$f" ]; then cat "$f"; else echo '{}'; fi; } | jq --argjson k "$(render antigravity)" '.["agentic-kit"] = $k';;
  esac
}
hooks_ok() {  # hooks_ok TOOL: are the kit's hooks in that tool's hook file?
  case "$1" in
    codex) codex_merge check >/dev/null;;
    antigravity) jq -e --argjson k "$(render antigravity)" '.["agentic-kit"] == $k' "$TH/.gemini/config/hooks.json" >/dev/null 2>&1;;
  esac
}
RULES_BEGIN='<!-- agentic-kit rules: install.sh --apply keeps this block current; write your own rules outside it -->'
rules_merged() {  # rules_merged FILE: print FILE with the kit's rules block added or brought up to date
  python3 - "$1" "$RULES_SRC" "$RULES_BEGIN" <<'PY'
import os, re, sys
f, src, b = sys.argv[1:4]
e = "<!-- /agentic-kit rules -->"
t = open(f).read() if os.path.exists(f) else ""
block = b + "\n" + open(src).read().rstrip("\n") + "\n" + e
old = re.compile(re.escape(b) + r".*?" + re.escape(e), re.S)
if old.search(t):   # brought up to date where it is, so your text after it stays after it
    sys.stdout.write(old.sub(lambda m: block, t, count=1))
else:
    t = t.rstrip("\n")
    print((t + "\n\n" if t else "") + block)
PY
}
rules_ok() {  # the tool's AGENTS.md is the kit's rules (a link) or holds the current block
  [ "$(state "$1" "$RULES_SRC")" = linked ] || { [ -f "$1" ] && [ "$(rules_merged "$1")" = "$(cat "$1")" ]; }
}
config_files() {  # yours after install: copied only if missing, never linked or replaced
  (cd "$REPO/claude" && { for c in guard.conf lanes.zsh; do [ -f "$c" ] && echo "$c"; done
    find roles agents -type f ! -name '.DS_Store' 2>/dev/null; } | sort)
}

managed() {  # program files: linked. Everything under claude/ except config, docs, synced skills and session state.
  (cd "$REPO/claude" && find . -type f ! -path './designs/*' ! -path './skills/synced/*' ! -path '*/.state/*' \
     ! -path './roles/*' ! -path './agents/*' \
     ! -name '.DS_Store' ! -name settings.json ! -name CLAUDE.md ! -name guard.conf ! -name lanes.zsh \
     | sed 's#^\./##' | sort)
}
touched() {  # every path --apply may change, relative to ~/.claude (or to your home: "@/")
  managed; echo kit; echo settings.json; echo CLAUDE.md; echo kit-tools
  config_files; tool_targets
}

state() {  # state TARGET SOURCE -> linked|file|link-elsewhere|missing
  if [ -L "$1" ]; then [ "$(readlink "$1")" = "$2" ] && echo linked || echo link-elsewhere
  elif [ -e "$1" ]; then echo file; else echo missing; fi
}

version_check() {  # hooks and settings keys used here need a recent Claude Code; warn, don't block
  local v; v=$(claude --version 2>/dev/null | awk '{print $1}')
  [ -n "$v" ] || { echo "NOTE: claude not found on PATH; install Claude Code before starting sessions."; return 0; }
  if [ "$(printf '%s\n%s\n' "$v" 2.1.290 | sort -V | head -1)" != 2.1.290 ]; then
    echo "NOTE: Claude Code $v is older than 2.1.290, the version this kit is tested with. Run: claude update"
  fi
  claude_at_least 2.1.295 || echo "NOTE: before Claude Code 2.1.295 a guard that times out or can't start lets the command run. Run: claude update, then ./install.sh --apply again."
}

claude_at_least() {  # claude_at_least 2.1.295: is the installed Claude Code that version or newer?
  local v; v=$(claude --version 2>/dev/null | awk '{print $1}')
  [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$v" "$1" | sort -V | head -1)" = "$1" ]
}
merged_settings() {  # print what settings.json would become
  # onFailure ("block" when a guard can't run or times out) arrived in 2.1.295; older versions get the hooks
  # without it, and --status tells them to update.
  local drop=""; claude_at_least 2.1.295 || drop=onFailure
  KIT_DROP_HOOK_KEYS=$drop python3 "$REPO/bin/settings-merge.py" merge "$CH/settings.json" "$KIT_SETTINGS"
}
kit_check() {  # are the kit's deny rules and hooks in your settings? (same version rule as merged_settings)
  local drop=""; claude_at_least 2.1.295 || drop=onFailure
  KIT_DROP_HOOK_KEYS=$drop python3 "$REPO/bin/settings-merge.py" check "$CH/settings.json" "$KIT_SETTINGS"
}
has_import() { [ -f "$CH/CLAUDE.md" ] && grep -qxF "$IMPORT" "$CH/CLAUDE.md"; }
own_claude_md() { [ "$(state "$CH/CLAUDE.md" "$REPO/claude/CLAUDE.md")" = linked ]; }  # it already IS the kit's file

case "$mode" in
dry|--dry-run)
  echo "DRY RUN: nothing changes. Repo: $REPO  Target: $CH"
  version_check
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
  [ "$(state "$CH/kit" "$REPO")" = linked ] || { echo "+ LINK  kit -> $REPO"; n=$((n + 1)); }
  if ! kit_check >/dev/null; then
    echo "~ MERGE settings.json (adds, never removes):"
    diff -u <(cat "$CH/settings.json" 2>/dev/null || true) <(merged_settings) | sed '1,2d' | sed 's/^/    /' || true
    n=$((n + 1))
  fi
  has_import || { echo "+ LINE  CLAUDE.md gets: $IMPORT"; n=$((n + 1)); }
  while read -r c; do
    [ -e "$CH/$c" ] || { echo "+ COPY  $c (yours to edit)"; n=$((n + 1)); }
  done < <(config_files)
  echo "Agent CLIs besides Claude Code: ${TOOLS:-none} (choose with --tool codex,opencode,antigravity|all|none)"
  while read -r rel; do
    dst=$(resolve "$rel")
    case "$rel" in
      */AGENTS.md) rules_ok "$dst" && continue
        if [ -e "$dst" ]; then echo "~ RULES $rel (your text stays; the kit's rules go in a marked block at the end)"
        else echo "+ LINK  $rel -> $RULES_SRC"; fi;;
      */agentic-kit.js) [ "$(state "$dst" "$(link_src "$rel")")" = linked ] && continue; echo "+ LINK  $rel -> $(link_src "$rel")";;
      */hooks.json) t=codex; case "$rel" in */.gemini/*) t=antigravity;; esac
        hooks_ok "$t" && continue
        echo "~ MERGE $rel (adds, never removes):"
        diff -u <(cat "$dst" 2>/dev/null || true) <(hooks_merged "$t") | sed '1,2d' | sed 's/^/    /' || true;;
    esac
    n=$((n + 1))
  done < <(tool_targets)
  echo "$n change(s) would be made. Apply with: $0 --apply   (rollback: $0 --rollback)";;

--apply)
  version_check
  command -v python3 >/dev/null || { echo "install: python3 is required (to merge settings.json)."; exit 1; }
  command -v jq >/dev/null || echo "NOTE: jq is not installed; the guard blocks every command until it is (brew/apt install jq)."
  # Validate your settings.json BEFORE touching anything: a file we can't parse is never overwritten.
  merged_settings > /dev/null || { echo "install: can't parse $CH/settings.json; fix it first. Nothing changed."; exit 1; }
  for t in $TOOLS; do
    case "$t" in codex|antigravity)
      hooks_merged "$t" > /dev/null 2>&1 || { echo "install: can't parse $t's hook file; fix it first. Nothing changed."; exit 1; };;
    esac
  done
  # A zero-padded sequence number first, so backups always sort in the order they were made.
  mkdir -p "$BK"; seq_n=$(( $(find "$BK" -mindepth 1 -maxdepth 1 -type d | wc -l) + 1 ))
  ts=$(printf '%04d' "$seq_n")-$(date +%Y%m%d-%H%M%S); dest="$BK/$ts"; mkdir -p "$dest"
  : > "$dest/manifest"
  while read -r rel; do
    dst=$(resolve "$rel"); src=$(link_src "$rel")
    s=$(state "$dst" "$src")
    echo "$s $rel" >> "$dest/manifest"
    # Back up what would be lost. A path already linked here holds nothing to lose, so rollback leaves it alone.
    if [ "$s" = file ] || [ "$s" = link-elsewhere ]; then
      mkdir -p "$dest/files/$(dirname "$rel")"; cp -P "$dst" "$dest/files/$rel"
    fi
  done < <(touched)
  # Folders this install creates are recorded too (deepest first), so a rollback leaves no empty ones behind.
  { managed; config_files; } | while read -r rel; do d=$(dirname "$rel"); while [ "$d" != . ]; do echo "$d"; d=$(dirname "$d"); done; done \
    | sort -ru | while read -r d; do [ -e "$CH/$d" ] || echo "newdir $d"; done >> "$dest/manifest"
  tool_targets | while read -r rel; do d=$(dirname "$rel"); while [ "$d" != @ ]; do echo "$d"; d=$(dirname "$d"); done; done \
    | sort -ru | while read -r d; do [ -e "$(resolve "$d")" ] || echo "newdir $d"; done >> "$dest/manifest"
  echo "Backup: $dest ($(wc -l < "$dest/manifest" | tr -d ' ') paths recorded)"
  mkdir -p "$CH"
  ln -sfn "$REPO" "$CH/kit"
  while read -r rel; do
    mkdir -p "$CH/$(dirname "$rel")"; ln -sfn "$REPO/claude/$rel" "$CH/$rel"
  done < <(managed)
  # settings.json: write the merge to a temp file, then move it into place (replaces a symlink, never writes through).
  merged_settings > "$CH/settings.json.kit-new" && mv "$CH/settings.json.kit-new" "$CH/settings.json"
  if ! has_import && ! own_claude_md; then
    if [ -L "$CH/CLAUDE.md" ]; then cp "$CH/CLAUDE.md" "$CH/CLAUDE.md.kit-new" && mv "$CH/CLAUDE.md.kit-new" "$CH/CLAUDE.md"; fi
    { [ -s "$CH/CLAUDE.md" ] && printf '\n# Agentic engineering kit (remove this line to stop loading it)\n'; echo "$IMPORT"; } >> "$CH/CLAUDE.md"
  fi
  while read -r c; do
    if [ ! -e "$CH/$c" ]; then mkdir -p "$CH/$(dirname "$c")"; cp "$REPO/claude/$c" "$CH/$c"; fi
  done < <(config_files)
  # The other agent CLIs: hook files merged through a temp file (like settings.json), the OpenCode plugin linked.
  for t in $TOOLS; do
    case "$t" in
      codex) mkdir -p "$TH/.codex"; hooks_merged codex > "$TH/.codex/hooks.json.kit-new" && mv "$TH/.codex/hooks.json.kit-new" "$TH/.codex/hooks.json";;
      antigravity) mkdir -p "$TH/.gemini/config"
        hooks_merged antigravity > "$TH/.gemini/config/hooks.json.kit-new" && mv "$TH/.gemini/config/hooks.json.kit-new" "$TH/.gemini/config/hooks.json";;
      opencode) mkdir -p "$TH/.config/opencode/plugins"; ln -sfn "$REPO/tools/opencode/agentic-kit.js" "$TH/.config/opencode/plugins/agentic-kit.js";;
    esac
  done
  while read -r rel; do
    case "$rel" in */AGENTS.md)
      f=$(resolve "$rel"); mkdir -p "$(dirname "$f")"
      if [ -L "$f" ] && [ ! -e "$f" ]; then rm -f "$f"; fi   # a dangling link holds nothing (and it's in the backup)
      if [ ! -e "$f" ]; then ln -s "$RULES_SRC" "$f"
      elif ! rules_ok "$f"; then rules_merged "$f" > "$f.kit-new" && mv "$f.kit-new" "$f"; fi;;
    esac
  done < <(tool_targets)
  if [ -n "$TOOLS" ]; then printf '%s\n' $TOOLS > "$CH/kit-tools"; else rm -f "$CH/kit-tools"; fi
  case " $TOOLS " in *" codex "*) echo "NOTE: Codex runs new hooks only after you review them: start codex and run /hooks once.";; esac
  # Merge queue state lives in $MERGE_STATE. Optional one-time copy from an older inline queue script.
  MS=${MERGE_STATE:-$HOME/.local/state/merge-queue}; OLD=${OLD_MERGE_DIR:-}
  mkdir -p "$MS"
  if [ -n "$OLD" ] && [ ! -f "$MS/queue.txt" ] && [ -f "$OLD/merge_next.sh" ]; then
    awk '/<<LIST/{f=1;next} /^LIST$/{f=0} f' "$OLD/merge_next.sh" > "$MS/queue.txt"
    [ -f "$OLD/verified.txt" ] && cp "$OLD/verified.txt" "$MS/verified.txt"
    echo "Merge queue copied from $OLD to $MS ($(grep -cv '^#' "$MS/queue.txt" || true) active lines)."
  fi
  /bin/bash "$REPO/install.sh" --status;;

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
    dst=$(resolve "$rel")
    case "$s" in
      linked) ;;                              # was already installed before this apply: nothing to restore
      newdir) rmdir "$dst" 2>/dev/null || true;;   # only if empty: anything you put there stays
      missing) rm -rf "$dst";;
      *) rm -f "$dst"; mkdir -p "$(dirname "$dst")"; cp -P "$last/files/$rel" "$dst";;
    esac
  done < "$last/manifest"
  echo "Rolled back to $last"
  mv "$last" "$last.rolled-back";;

--status)
  if [ ! -L "$CH/kit" ] && [ -z "$(find "$CH" -type l 2>/dev/null | head -1)" ]; then
    echo "NOT INSTALLED: nothing from the kit is in $CH (install with: ./install.sh --apply)"; exit 1
  fi
  bad=0
  while read -r rel; do
    s=$(state "$CH/$rel" "$REPO/claude/$rel")
    [ "$s" = linked ] || { echo "DRIFT $s $rel"; bad=1; }
  done < <(managed)
  [ "$(state "$CH/kit" "$REPO")" = linked ] || { echo "DRIFT kit does not link to $REPO"; bad=1; }
  miss=$(kit_check) \
    || { bad=1; printf '%s\n' "$miss" | sed 's/^/DRIFT settings.json /'; }
  has_import || own_claude_md || { echo "DRIFT CLAUDE.md lacks: $IMPORT"; bad=1; }
  for t in $TOOLS; do   # the agent CLIs the last --apply set up (kit-tools)
    case "$t" in
      codex|antigravity) hooks_ok "$t" || { echo "DRIFT $t: the kit's hooks are missing from its hook file"; bad=1; };;
      opencode) [ "$(state "$TH/.config/opencode/plugins/agentic-kit.js" "$REPO/tools/opencode/agentic-kit.js")" = linked ] \
        || { echo "DRIFT opencode: plugins/agentic-kit.js does not link to the kit"; bad=1; };;
    esac
  done
  while read -r rel; do
    case "$rel" in */AGENTS.md) rules_ok "$(resolve "$rel")" || { echo "DRIFT ${rel#@/} lacks the kit's current rules"; bad=1; };; esac
  done < <(tool_targets)
  [ $bad = 0 ] && echo "STATUS OK: kit linked, program files linked, settings rules and hooks present${TOOLS:+; also set up: $TOOLS}" \
    || { echo "STATUS: drift found (re-run --apply, or --rollback)"; exit 1; };;

*) awk 'NR > 1 && /^set -euo/ { exit } NR > 1' "$0"; exit 2;;   # the whole header comment
esac
