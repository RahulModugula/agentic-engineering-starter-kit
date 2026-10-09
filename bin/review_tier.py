#!/usr/bin/env python3
"""review_tier.py: decide whether a change needs a HUMAN review or may merge on the AI verifier alone.

Policy file: `.review-tiers` at the repo root, read from the BASE branch (a PR can't loosen its own policy):

    # tier  glob                      (gitignore-style globs; ** = any depth)
    default human                     # unlisted paths: human (fail closed). Optional; human if omitted.
    agent   web/**                    # UI/UX
    agent   tests/**
    agent   bench/**
    human   src/auth/**               # human rules win over agent rules, whatever their order

A change is HUMAN when any of these hold (each is listed as a reason):
  - a changed path (or a renamed file's OLD path) matches a human rule or no rule (default human);
  - the policy file `.review-tiers` itself changes;
  - a test file is deleted, or a test file loses more assertion lines than it gains (weakened tests);
  - the PR's file list can't be read (fail closed).
Otherwise it is AGENT: the AI verifier's VERIFIED is enough.

  review_tier.py --local [--repo DIR] [--base origin/main] [--head HEAD]
  review_tier.py --pr OWNER/REPO NUMBER [--base-ref main]
Prints JSON {"tier", "reasons", "human_files", "files"}; exit 0 = agent, 10 = human, 2 = usage/error (treat as human).
"""
import argparse, json, re, subprocess, sys

POLICY = ".review-tiers"
# A file a test runner would actually collect (by name). Renaming one to anything else disables it.
RUNNABLE_TEST = re.compile(r"(^|/)test_[^/]*\.py$|_test\.(py|go)$|\.(test|spec)\.[jt]sx?$|(^|/)tests?/[^/]*\.(py|[jt]sx?|go|rb|rs)$")
TEST_PATH = re.compile(r"(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]*\.py$|_test\.(py|go)$|\.(test|spec)\.[jt]sx?$")
ASSERT = re.compile(r"\b(assert|expect\s*\(|assertEqual|assertTrue|assertRaises|pytest\.raises|should\.)")
# An assertion that can't fail: swapping a real check for one of these keeps the assert count equal.
WEAK_ASSERT = re.compile(r"\bassert\s+(True|1|not\s+False)\b|assertTrue\(\s*True\s*\)|expect\(\s*(true|1)\s*\)\.toBe(\(\s*true\s*\)|Truthy)|expect\(true\)")
SNAPSHOT_PATH = re.compile(r"(^|/)(__snapshots__|golden|goldens)/|\.snap$")
EXCLUSION = re.compile(r"pragma:\s*no\s*(cover|mutate)|istanbul ignore|c8 ignore|\bnosec\b|eslint-disable")
FLAKY = re.compile(r"mark\.flaky|\breruns\s*=|jest\.retryTimes|\.retries\(|\bquarantine\b", re.I)
SKIP = re.compile(r"@pytest\.mark\.(skip|xfail)|pytest\.skip\(|\b(it|test|describe)\.(skip|only)\(|\bx(it|describe)\(|unittest\.skip|t\.Skip\(")

def glob_re(g):
    """gitignore-ish glob -> regex. `**` any depth, `*` within a segment, trailing `/` = directory."""
    g = g.strip()
    if g.endswith("/"): g += "**"
    anchored = "/" in g.rstrip("/").lstrip("/") or g.startswith("/")
    g = g.lstrip("/")
    plain = not any(c in g for c in "*?[")   # `human src/auth` means the path AND everything under it
    out, i = "", 0
    while i < len(g):
        if g[i:i + 3] == "**/": out += "(?:.*/)?"; i += 3
        elif g[i:i + 2] == "**": out += ".*"; i += 2
        elif g[i] == "*": out += "[^/]*"; i += 1
        elif g[i] == "?": out += "[^/]"; i += 1
        else: out += re.escape(g[i]); i += 1
    return re.compile(("^" if anchored else "^(?:.*/)?") + out + ("(?:/.*)?" if plain else "") + "$")

def parse_policy(text):
    """Returns (rules, default, escalate). `escalate <ERE>` lines: an ADDED line matching ERE in an agent-tier file
    makes the change human (e.g. an agent-only UI file starting to import the database or auth code)."""
    rules, default, escalate = [], "human", []
    for ln in (text or "").splitlines():
        if ln.lstrip().startswith("escalate"):
            pat = ln.lstrip()[len("escalate"):].strip()
            if pat: escalate.append(re.compile(pat))
            continue
        ln = ln.split("#", 1)[0].strip()
        if not ln: continue
        parts = ln.split(None, 1)
        if len(parts) != 2: continue
        tier, pat = parts[0].lower(), parts[1].strip()
        if tier == "default" and pat in ("human", "agent"): default = pat
        elif tier in ("human", "agent"): rules.append((tier, glob_re(pat), pat))
    return rules, default, escalate

def classify_path(path, rules, default):
    tiers = {t for t, rx, _ in rules if rx.match(path)}
    if "human" in tiers: return "human", "matches a human rule"
    if "agent" in tiers: return "agent", ""
    return default, "" if default == "agent" else "no rule matches (default human)"

def decide(files, policy_text):
    """files: list of {path, status(A/M/D/R), old_path?, removed_asserts, added_asserts}"""
    rules, default, escalate = parse_policy(policy_text)
    reasons, human_files = [], []
    for f in files:
        if f.get("truncated"):
            reasons.append(f"{f['path']}: the PR's file list is truncated, so it can't be fully checked; fail closed")
            human_files.append(f["path"]); continue
        tier_new = None
        for p in [f["path"]] + ([f["old_path"]] if f.get("old_path") else []):
            if p == POLICY:
                reasons.append(f"{p}: the review policy itself changed"); human_files.append(p); continue
            t, why = classify_path(p, rules, default)
            if p == f["path"]: tier_new = t
            if t == "human":
                reasons.append(f"{p}: {why}"); human_files.append(p)
        if f.get("patch") is None and f["status"] != "D" and tier_new == "agent" and (escalate or TEST_PATH.search(f["path"])):
            reasons.append(f"{f['path']}: diff not available (too large?), can't check it; fail closed")
            human_files.append(f["path"])
        added = [ln[1:] for ln in (f.get("patch") or "").splitlines() if ln.startswith("+") and not ln.startswith("+++")]
        # Ways to turn red green without fixing anything: regenerate a snapshot, exclude code from coverage or
        # mutation, or mark a test flaky. Each needs a person, whatever the path's tier.
        if SNAPSHOT_PATH.search(f["path"]) and f["status"] in ("M", "D", "R"):
            reasons.append(f"{f['path']}: snapshot/golden output rewritten"); human_files.append(f["path"])
        if any(EXCLUSION.search(ln) for ln in added):
            reasons.append(f"{f['path']}: adds a coverage/mutation/lint exclusion"); human_files.append(f["path"])
        if any(FLAKY.search(ln) for ln in added):
            reasons.append(f"{f['path']}: marks a test flaky or adds retries"); human_files.append(f["path"])
        if tier_new == "agent":
            for rx in escalate:
                if any(rx.search(ln) for ln in added):
                    reasons.append(f"{f['path']}: agent-tier file adds a line matching escalate /{rx.pattern}/")
                    human_files.append(f["path"]); break
        if f.get("old_path") and RUNNABLE_TEST.search(f["old_path"]) and not RUNNABLE_TEST.search(f["path"]):
            reasons.append(f"{f['old_path']}: test file renamed out of the tests (a disguised deletion)")
            human_files.append(f["old_path"])
        if TEST_PATH.search(f["path"]):
            if f["status"] == "D":
                reasons.append(f"{f['path']}: test file deleted"); human_files.append(f["path"])
            elif f.get("removed_asserts", 0) > f.get("added_asserts", 0):
                reasons.append(f"{f['path']}: assertions removed ({f['removed_asserts']} out, {f['added_asserts']} in)")
                human_files.append(f["path"])
            if f.get("removed_asserts", 0) and any(WEAK_ASSERT.search(ln) for ln in added):
                reasons.append(f"{f['path']}: an assertion was replaced by one that can't fail"); human_files.append(f["path"])
            if any(SKIP.search(ln) for ln in added):
                reasons.append(f"{f['path']}: a test is newly skipped/xfail/only"); human_files.append(f["path"])
    hf = sorted(set(human_files))
    return {"tier": "human" if hf else "agent", "reasons": reasons, "human_files": hf,
            "files": sorted({f["path"] for f in files})}

def count_asserts(patch):
    rem = add = 0
    for ln in (patch or "").splitlines():
        if ln.startswith("-") and not ln.startswith("---") and ASSERT.search(ln): rem += 1
        elif ln.startswith("+") and not ln.startswith("+++") and ASSERT.search(ln): add += 1
    return rem, add

def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True).stdout

def local_files(repo, base, head):
    files = []
    # -z: NUL-separated and unquoted, so paths with spaces or non-ASCII characters match the policy globs.
    tok = run(["git", "diff", "--name-status", "-z", "-M", f"{base}...{head}"], repo).split("\0")
    i = 0
    while i < len(tok) and tok[i]:
        st = tok[i][0]
        if st in "RC":
            parts = [tok[i], tok[i + 1], tok[i + 2]]; i += 3
        else:
            parts = [tok[i], tok[i + 1]]; i += 2
        f: dict = {"status": "R" if st == "R" else ("A" if st == "C" else st), "path": parts[-1]}
        if st == "R": f["old_path"] = parts[1]
        patch = run(["git", "diff", f"{base}...{head}", "--", parts[-1]], repo) if st != "D" else ""
        rem, add = count_asserts(patch)
        f["removed_asserts"], f["added_asserts"], f["patch"] = rem, add, patch
        files.append(f)
    try: policy = run(["git", "show", f"{base}:{POLICY}"], repo)
    except subprocess.CalledProcessError: policy = None   # the file doesn't exist on the base branch
    return files, policy

def pr_files(repo, num, base_ref):
    # --slurp wraps every page in one array; without it, pages print back to back and aren't one JSON document.
    pages = json.loads(run(["gh", "api", "--paginate", "--slurp", f"repos/{repo}/pulls/{num}/files?per_page=100"]))
    raw = [x for page in pages for x in (page if isinstance(page, list) else [page])]
    st_map = {"added": "A", "removed": "D", "modified": "M", "renamed": "R", "changed": "M", "copied": "A"}
    files = []
    for x in raw:
        rem, add = count_asserts(x.get("patch"))
        f: dict = {"path": x["filename"], "status": st_map.get(x["status"], "M"), "removed_asserts": rem,
                   "added_asserts": add, "patch": x.get("patch")}  # GitHub omits patch for very large diffs
        if x.get("previous_filename"): f["old_path"] = x["previous_filename"]
        files.append(f)
    meta = json.loads(run(["gh", "pr", "view", str(num), "-R", repo, "--json", "baseRefName,changedFiles"]))
    base_ref = base_ref or meta["baseRefName"]
    # GitHub lists at most 3000 files per PR: a shorter list than changedFiles means some files went unseen.
    if len(raw) >= 3000 or len(raw) != meta.get("changedFiles", len(raw)):
        files.append({"path": f"<{meta.get('changedFiles')} files; only {len(raw)} listed>", "status": "M",
                      "patch": None, "truncated": True})
    try:
        policy = run(["gh", "api", f"repos/{repo}/contents/{POLICY}?ref={base_ref}", "-H", "Accept: application/vnd.github.raw+json"])
    except subprocess.CalledProcessError as e:
        if "HTTP 404" not in (e.stderr or ""):   # only "not found" means no policy; an outage must fail closed
            raise
        policy = None
    return files, policy

def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = a.add_mutually_exclusive_group(required=True)
    g.add_argument("--local", action="store_true"); g.add_argument("--pr", nargs=2, metavar=("REPO", "NUMBER"))
    a.add_argument("--repo", default="."); a.add_argument("--base", default="origin/main"); a.add_argument("--head", default="HEAD")
    a.add_argument("--base-ref")
    o = a.parse_args()
    try:
        files, policy = local_files(o.repo, o.base, o.head) if o.local else pr_files(o.pr[0], o.pr[1], o.base_ref)
    except Exception as e:  # fail closed
        print(json.dumps({"tier": "human", "policy_found": None, "reasons": [f"could not read the change: {e}"],
                          "human_files": [], "files": []}))
        sys.exit(2)
    try:
        r = decide(files, policy or "")
    except Exception as e:  # a checker bug must fail closed too, with a reason, not a bare traceback
        print(json.dumps({"tier": "human", "policy_found": None, "reasons": [f"review_tier error: {e}"],
                          "human_files": [], "files": [f["path"] for f in files]}))
        sys.exit(2)
    # Callers decide "tiering off" ONLY from this boolean, never from reason text (a file name could imitate it).
    # It means "the file exists": an EMPTY policy is a policy (everything defaults to human), not "tiering off".
    r["policy_found"] = policy is not None
    if policy is None: r["reasons"].insert(0, "no .review-tiers on the base branch: every path defaults to human")
    print(json.dumps(r, indent=2))
    sys.exit(10 if r["tier"] == "human" else 0)

if __name__ == "__main__":
    main()
