#!/usr/bin/env python3
"""settings-merge.py merge|check USER_SETTINGS KIT_SETTINGS

merge: print USER_SETTINGS with the kit's settings ADDED, never removing anything of yours:
  - permissions.deny / allow / ask and autoMode.* lists: union (your entries first, kit entries appended if missing);
  - hooks.<Event>: the kit's hook groups appended unless an identical command is already there;
  - every other kit key (e.g. statusLine, permissions.disableBypassPermissionsMode): set only if you don't have it.
  KIT_DROP_HOOK_KEYS=a,b drops those keys from the kit's hook entries first (the installer uses it to leave out
  keys an older Claude Code doesn't know, such as onFailure before 2.1.295).
check: exit 0 if every kit deny rule and hook command is present in USER_SETTINGS, else 1 (lists what's missing).
A missing or empty USER_SETTINGS counts as {}.
"""
import json, os, sys

UNION_SECTIONS = ("permissions", "autoMode")


def load(p):
    if not os.path.exists(p) or os.path.getsize(p) == 0:
        return {}
    with open(p) as f:
        return json.load(f)


def commands(groups):
    return {h.get("command") for g in groups or [] for h in g.get("hooks", [])}


def drop_hook_keys(k):
    drop = [x for x in os.environ.get("KIT_DROP_HOOK_KEYS", "").split(",") if x]
    for groups in (k.get("hooks") or {}).values():
        for g in groups:
            for h in g.get("hooks", []):
                for key in drop:
                    h.pop(key, None)
    return k


def merge(u, k):
    out = json.loads(json.dumps(u))
    k = drop_hook_keys(json.loads(json.dumps(k)))
    for section in UNION_SECTIONS:
        if section not in k:
            continue
        mine = out.setdefault(section, {})
        for key, val in k[section].items():
            if isinstance(val, list):
                cur = mine.setdefault(key, [])
                cur.extend(x for x in val if x not in cur)
            elif key not in mine:
                mine[key] = val
    hooks = out.setdefault("hooks", {})
    for event, groups in (k.get("hooks") or {}).items():
        cur = hooks.setdefault(event, [])
        have = commands(cur)
        for g in groups:
            if not commands([g]) <= have:
                cur.append(g)
                have |= commands([g])
        # An entry you already have for a kit command gains the kit's keys you lack (e.g. onFailure after an
        # update); keys you set are never changed.
        kit_entries = {h.get("command"): h for g in groups for h in g.get("hooks", [])}
        for g in cur:
            for h in g.get("hooks", []):
                for key, val in kit_entries.get(h.get("command"), {}).items():
                    h.setdefault(key, val)
    for key, val in k.items():
        if key not in UNION_SECTIONS + ("hooks",) and key not in out:
            out[key] = val
    return out


def missing(u, k):
    k = drop_hook_keys(json.loads(json.dumps(k)))
    miss = [f"deny: {d}" for d in (k.get("permissions") or {}).get("deny", [])
            if d not in (u.get("permissions") or {}).get("deny", [])]
    for event, groups in (k.get("hooks") or {}).items():
        mine = (u.get("hooks") or {}).get(event)
        have = commands(mine)
        miss += [f"hook {event}: {c}" for c in commands(groups) - have]
        mine_entries = {h.get("command"): h for g in mine or [] for h in g.get("hooks", [])}
        for g in groups:
            for h in g.get("hooks", []):
                if h.get("command") in mine_entries and "onFailure" in h and "onFailure" not in mine_entries[h["command"]]:
                    miss.append(f"hook {event}: {h['command']} lacks onFailure (re-run ./install.sh --apply)")
    return miss


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("merge", "check"):
        sys.exit(__doc__)
    user, kit = load(sys.argv[2]), load(sys.argv[3])
    if sys.argv[1] == "merge":
        print(json.dumps(merge(user, kit), indent=2))
    else:
        m = missing(user, kit)
        for x in m:
            print("MISSING", x)
        sys.exit(1 if m else 0)
