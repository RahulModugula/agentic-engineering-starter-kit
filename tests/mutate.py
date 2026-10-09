#!/usr/bin/env python3
"""Mutation check: prove each test can FAIL. For every line in tests/mutants.txt, copy the repo to a scratch dir,
break one rule (exact text replacement), run that rule's test file, and require it to fail. A surviving mutant is a
test gap. Run: python3 tests/mutate.py [-j N]. Exit 0 only if every mutant is killed and none is stale."""
import argparse, concurrent.futures as cf, os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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

def run_one(m):
    n, path, test, frm, to = m
    src = os.path.join(ROOT, path)
    if not os.path.exists(src):
        return n, "skipped", f"{path} not in this repo"
    text = open(src).read()
    if frm not in text:
        return n, "STALE", f"{path}: text not found: {frm!r}"
    with tempfile.TemporaryDirectory(prefix="mutant.") as d:
        dst = os.path.join(d, "repo")
        shutil.copytree(ROOT, dst, ignore=shutil.ignore_patterns(".git", "dist", "__pycache__"), symlinks=True)
        with open(os.path.join(dst, path), "w") as f:
            f.write(text.replace(frm, to, 1))
        r = subprocess.run(["/bin/bash", os.path.join(dst, "tests", test)], capture_output=True, text=True,
                           env={**os.environ, "TEST_FILE": test}, timeout=600)
        return n, "killed" if r.returncode != 0 else "SURVIVED", f"{path} [{frm[:50]}] via {test}"

def main():
    a = argparse.ArgumentParser(); a.add_argument("-j", type=int, default=os.cpu_count() or 4); o = a.parse_args()
    ms = load()
    with cf.ThreadPoolExecutor(max_workers=o.j) as ex:
        res = sorted(ex.map(run_one, ms))
    for n, status, why in res:
        if status != "killed":
            print(f"  {status:8} mutants.txt:{n}  {why}")
    k = sum(s == "killed" for _, s, _ in res); bad = [r for r in res if r[1] in ("SURVIVED", "STALE")]
    sk = sum(s == "skipped" for _, s, _ in res)
    print(f"mutation: {k}/{len(res) - sk} killed, {len(bad)} survived/stale, {sk} skipped (file not in this repo)")
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
