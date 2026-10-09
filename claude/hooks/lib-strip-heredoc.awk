# Emit only the shell command itself, dropping heredoc bodies.
# Without this, a guard matches text the command merely *writes to a file*
# (e.g. a doc that mentions `--profile production`) instead of what it runs.
{
  if (inhere) {
    if ($0 == delim || $0 ~ "^[[:space:]]*" delim "[[:space:]]*$") inhere = 0
    next
  }
  line = $0
  if (match(line, /<<-?[[:space:]]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
    tok = substr(line, RSTART, RLENGTH)
    gsub(/^<<-?[[:space:]]*/, "", tok)
    gsub(/[\047"]/, "", tok)
    delim = tok
    inhere = 1
  }
  print line
}
