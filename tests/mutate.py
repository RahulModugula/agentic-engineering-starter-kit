#!/usr/bin/env python3
"""Mutation check: prove each test can FAIL. For every line in tests/mutants.txt, copy the repo to a scratch dir,
break one rule (exact text replacement), run that rule's test file, and require an assertion in it to fail.
A surviving mutant is a test gap. Run: python3 tests/mutate.py [-j N].

Statuses (everything except killed/skipped fails the run):
  killed     the test exited non-zero AND printed an assertion failure ("FAIL [")
  SURVIVED   the test passed with the rule broken: a test gap
  ERROR      the test exited non-zero without any assertion failing (crash, syntax error, timeout): a broken
             mutant, which proves nothing about the tests
  STALE      the target text is not in the file (0 occurrences)
  AMBIGUOUS  the target text occurs more than once, so which rule was broken is unclear; make it longer
  DUPLICATE  same file and same target text as an earlier line
  skipped    the file is not in this repo
Before any mutant runs, every referenced test file is run once UNMUTATED in its own scratch copy and must pass;
mutants against a red test prove nothing, so a failing baseline stops the run."""
import argparse, concurrent.futures as cf, os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSERT_FAIL = "FAIL ["
TIMEOUT = 600

def load():
    out = []
    for n, ln in enumerate(open(os.path.join(ROOT, "tests", "mutants.txt")), 1):
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        parts = [p.strip() for p in ln.rstrip("\n").split(" | ")]
        if len(parts) != 4:
            sys.exit(f"mutants.txt:{n}: need 'file | test | from | to', got {len(parts)} fields")
        out.append((n, *parts))
    return out

def run_test(test, mutate=None):
    """Copy the repo, optionally apply (path, new_text), run tests/<test>. Returns (rc, output); rc None = timeout."""
    with tempfile.TemporaryDirectory(prefix="mutant.") as d:
        dst = os.path.join(d, "repo")
        shutil.copytree(ROOT, dst, ignore=shutil.ignore_patterns(".git", "dist", "__pycache__"), symlinks=True)
        if mutate:
            with open(os.path.join(dst, mutate[0]), "w") as f:
                f.write(mutate[1])
        try:
            r = subprocess.run(["/bin/bash", os.path.join(dst, "tests", test)], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, env={**os.environ, "TEST_FILE": test},
                               timeout=TIMEOUT)
        except subprocess.TimeoutExpired as e:
            out = e.stdout or ""
            return None, out.decode(errors="replace") if isinstance(out, bytes) else out
        return r.returncode, r.stdout

def classify(m, seen):
    """Static checks, before anything runs. Returns (n, status, why) or None if the mutant should run."""
    n, path, test, frm, to = m
    src = os.path.join(ROOT, path)
    if not os.path.exists(src):
        return n, "skipped", f"{path} not in this repo"
    key = (path, frm)
    if key in seen:
        return n, "DUPLICATE", f"{path}: same file and target as mutants.txt:{seen[key]}: {frm!r}"
    seen[key] = n
    c = open(src).read().count(frm)
    if c == 0:
        return n, "STALE", f"{path}: 0 occurrences of target text: {frm!r}"
    if c > 1:
        return n, "AMBIGUOUS", f"{path}: {c} occurrences of target text (needs exactly 1; make it longer): {frm!r}"
    return None

def run_one(m):
    n, path, test, frm, to = m
    text = open(os.path.join(ROOT, path)).read()
    if text.count(frm) != 1:  # changed under us since classify (someone is editing it)
        return n, "STALE", f"{path}: target text now occurs {text.count(frm)} times (file changed mid-run): {frm!r}"
    rc, out = run_test(test, (path, text.replace(frm, to, 1)))
    where = f"{path} [{frm[:50]}] via {test}"
    if rc is None:
        return n, "ERROR", f"{where}: timed out after {TIMEOUT}s"
    if rc == 0:
        return n, "SURVIVED", where
    if ASSERT_FAIL in out:
        return n, "killed", where
    tail = " | ".join(l.strip() for l in out.strip().splitlines()[-3:] if l.strip())
    return n, "ERROR", f"{where}: exit {rc} with no assertion failure (broken mutant); last output: {tail[:300]}"

def main():
    a = argparse.ArgumentParser(); a.add_argument("-j", type=int, default=os.cpu_count() or 4)
    a.add_argument("--only", default="", help="run only mutants whose file path contains this text")
    o = a.parse_args()
    ms = [m for m in load() if o.only in m[1]]
    seen, res, todo = {}, [], []
    for m in ms:
        r = classify(m, seen)
        (res.append(r) if r else todo.append(m))

    with cf.ThreadPoolExecutor(max_workers=o.j) as ex:
        tests = sorted({m[2] for m in todo})
        base = dict(zip(tests, ex.map(run_test, tests)))
        red = [(t, rc, out) for t, (rc, out) in base.items() if rc != 0]
        if red:
            for n, status, why in sorted(r for r in res if r[1] != "skipped"):  # static findings still count
                print(f"  {status:9} mutants.txt:{n}  {why}")
            for t, rc, out in red:
                why = "timed out" if rc is None else f"exit {rc}"
                print(f"  BASELINE {t}: {why} with no mutation")
                for l in out.splitlines():
                    if ASSERT_FAIL in l or l.startswith(t + ":"):
                        print(f"    {l.strip()}")
            sys.exit(f"mutation: baseline failed for {len(red)} test file(s); fix them before mutating "
                     f"(a mutant against a red test proves nothing)")
        print(f"baseline: {len(tests)} test file(s) pass unmutated")
        res += ex.map(run_one, todo)

    res.sort()
    for n, status, why in res:
        if status != "killed":
            print(f"  {status:9} mutants.txt:{n}  {why}")
    cnt = {s: sum(r[1] == s for r in res)
           for s in ("killed", "SURVIVED", "ERROR", "STALE", "AMBIGUOUS", "DUPLICATE", "skipped")}
    total = len(res) - cnt["skipped"]
    print(f"mutation: {cnt['killed']}/{total} killed, {cnt['SURVIVED']} survived, {cnt['ERROR']} error, "
          f"{cnt['STALE']} stale, {cnt['AMBIGUOUS']} ambiguous, {cnt['DUPLICATE']} duplicate, "
          f"{cnt['skipped']} skipped (file not in this repo)")
    sys.exit(0 if cnt["killed"] == total else 1)

if __name__ == "__main__":
    main()
