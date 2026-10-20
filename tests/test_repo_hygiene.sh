#!/bin/bash
# Repo hygiene: every script is executable and starts with a shebang; no Windows line endings; JSON parses.
. "$(dirname "$0")/lib.sh"
cd "$ROOT" || exit 1
bad=""
for f in install.sh bin/*.sh bin/*.py claude/hooks/*.sh tests/*.sh tests/fixtures/fake-gh .githooks/pre-commit; do
  [ -f "$f" ] || continue
  [ "$f" = tests/lib.sh ] && continue   # sourced, not run
  [ -x "$f" ] || bad="$bad $f(not-executable)"
  head -c 2 "$f" | grep -q '^#!' || bad="$bad $f(no-shebang)"
done
eq "every script is executable with a shebang" "${bad:-none}" "none"
crlf=$(grep -rlI $'\r' --exclude-dir=.git . 2>/dev/null | head -3)
eq "no CRLF line endings" "${crlf:-none}" "none"
for j in claude/settings.json kit/claude/settings.json tools/*/hooks.json; do if [ -f "$j" ]; then ok "$j parses" jq -e . "$j"; fi; done
# Workflow files: a step glued onto the previous line (a lost newline) would turn the CI run red.
glued=$(grep -nE '[^[:space:]][[:space:]]+- (name|uses|run):' .github/workflows/*.yml company/.github/workflows/*.yml 2>/dev/null | head -3)
eq "no workflow step is glued onto the line before it" "${glued:-none}" "none"
# Hooks must work on anyone's machine: no absolute home paths (they fail silently elsewhere).
abs=$(grep -lE '/(Users|home)/[a-z]' claude/hooks/* claude/lib/* claude/guard.conf 2>/dev/null | head -3)
eq "no hook, lib or guard.conf hardcodes a home directory" "${abs:-none}" "none"
abs=$(jq -r '[.hooks[]?[]?.hooks[]?.command, .statusLine.command] | .[] | select(.)' claude/settings.json | grep -E '^/(Users|home)/' | head -2)
eq "no settings.json hook command hardcodes a home directory" "${abs:-none}" "none"
finish
