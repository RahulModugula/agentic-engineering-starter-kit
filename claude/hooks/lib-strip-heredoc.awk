# Emit only the shell command itself, dropping heredoc BODIES, so a guard doesn't match text a command merely writes
# to a file (e.g. a doc that mentions `git push origin main`).
# Safe by construction: `<<<` (a here-string) and `<<` inside $(( )) are not heredocs; and if the closing delimiter
# never arrives (so it wasn't a heredoc after all), every held line is printed at the end, so nothing is hidden.
{
  if (inhere) {
    buf = buf $0 "\n"
    if ($0 == delim || $0 ~ "^[[:space:]]*" delim "[[:space:]]*$") { inhere = 0; buf = "" }
    next
  }
  line = $0
  probe = line
  gsub(/<<</, "", probe)                       # here-strings
  gsub(/\$\(\([^)]*\)\)/, "", probe)           # arithmetic: $((1<<X))
  if (match(probe, /<<-?[[:space:]]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
    tok = substr(probe, RSTART, RLENGTH)
    gsub(/^<<-?[[:space:]]*/, "", tok)
    gsub(/[\047"]/, "", tok)
    delim = tok
    inhere = 1
    buf = ""
  }
  print line
}
END { if (inhere) printf "%s", buf }
