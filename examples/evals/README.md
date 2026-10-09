# A small private eval for your agent setup

Re-run it whenever you change a prompt, a hook, a role or the model, and compare with the last run.

## Task format (one folder per task)

```
evals/tasks/0001-fix-date-parsing/
  task.md          # what you'd tell the agent, written as you would in a real lane brief
  repo.ref         # the git sha to start from
  hidden_tests/    # tests the agent never sees: they FAIL before the fix and PASS after
  check.sh         # copies hidden_tests in, runs them, and exits 0 on pass
```

## Running

For each task, k times (start with k=3):
1. Create a fresh worktree at `repo.ref`.
2. Run the agent on `task.md`, with your normal setup and a budget cap: `claude -p "$(cat task.md)" --max-budget-usd 2`.
3. Run `check.sh`. Record pass or fail, the cost, and the time.

Report **pass@k** (any try passed), **pass^k** (all k passed: consistency matters for unattended work) and the
mean cost. Start with 20–50 tasks taken from real bugs and features in your own history; the ones that failed
before are the most valuable.
