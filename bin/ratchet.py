#!/usr/bin/env python3
"""A baseline that may only shrink. Generic: any counter you already have (complexity per function, broad excepts
per file, `noqa` per module) writes {"key": count} JSON; this compares it with a committed baseline.

  ratchet.py check  BASELINE CURRENT [--report-only]   fail if any count rose or a new key appeared with count > 0
  ratchet.py shrink BASELINE CURRENT                   rewrite BASELINE from CURRENT; refuses if anything rose

Exit: 0 ok, 1 a count rose (check; with --report-only it prints the rises and exits 0), 2 bad input or usage.
Soft first: start with `check --report-only` in CI, then drop the flag once the baseline is committed and the
numbers are stable. A deliberate rise is made by hand-editing the baseline in a PR that lists the key and number.
Counts are non-negative integers; a count of 0 is dropped from the baseline, so a fixed key can't come back free."""
import json
import sys


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def load(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        die(f"ratchet: cannot read {path}: {e}")
    if not isinstance(data, dict):
        die(f"ratchet: {path}: expected a JSON object of key -> count")
    for k, v in data.items():
        if isinstance(v, bool) or not isinstance(v, int) or v < 0:
            die(f"ratchet: {path}: {k!r}: count must be a non-negative integer, got {v!r}")
    return data


def compare(baseline, current):
    """Return (rises, drops) as lists of (key, before, after)."""
    rises, drops = [], []
    for k in sorted(set(baseline) | set(current)):
        before, after = baseline.get(k, 0), current.get(k, 0)
        if after > before:
            rises.append((k, before, after))
        elif after < before:
            drops.append((k, before, after))
    return rises, drops


def show(label, rows):
    for k, before, after in rows:
        print(f"  {label} {k}: {before} -> {after}")


def main(argv):
    report_only = "--report-only" in argv
    args = [a for a in argv if a != "--report-only"]
    if len(args) != 3 or args[0] not in ("check", "shrink") or (report_only and args[0] != "check"):
        die(__doc__)
    cmd, base_path, cur_path = args
    baseline, current = load(base_path), load(cur_path)
    rises, drops = compare(baseline, current)
    if rises:
        print(f"ratchet: {len(rises)} count(s) rose")
        show("UP", rises)
    show("down", drops)
    if cmd == "check":
        if rises and not report_only:
            return 1
        print("ratchet: ok" if not rises else "ratchet: report only, not failing")
        return 0
    if rises:
        print("ratchet: refusing to rewrite the baseline while a count is up")
        return 1
    kept = {k: v for k, v in sorted(current.items()) if v > 0}
    with open(base_path, "w") as f:
        json.dump(kept, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"ratchet: baseline now has {len(kept)} key(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
