#!/usr/bin/env python3
"""The swarm planner: coverage.json (made by the game, tests/bots/coverage.gd) -> plan.json.

115 bots: 35 Linux jobs x 3 instances + 5 Mac jobs x 2. Every "test" entry of COVERAGE.md is assigned to
at least one bot of the role that exercises it; every bot gets a seed derived from the run number and its
id, both logged, so a bug replays with the same role, seed, world seed and assignment.
  swarm_plan.py coverage.json RUN_NUMBER plan.json
"""
import json, sys, hashlib

cov = json.load(open(sys.argv[1]))
run = int(sys.argv[2])
cats = cov["cats"]


def ids(cat, only_test=True):
    out = []
    for name, (label, status) in sorted(cats.get(cat, {}).items()):
        if only_test and not str(status).startswith("test"):
            continue
        out.append(f"{cat}:{name}")
    return out


def bseed(bot):
    return int(hashlib.sha256(f"{run}:{bot}".encode()).hexdigest()[:7], 16)


# torture entries are part:action; a bot takes a part and tries every action offered for it
torture_parts = sorted({i.split(":")[1] for i in ids("torture")})
pools = {
    "mapgen": ids("map"),
    "explorer": ids("district") + ids("building"),
    "collision": ids("collide"),
    "combat": ids("weapon") + ids("npc"),
    "mechanic": ids("exec") + ids("captive") + [f"torture:{p}" for p in torture_parts] + ids("carmenu") + ids("mech") + ids("save"),
    "item": ids("weapon") + ids("pocket"),
    "ui": ids("app") + ids("menu") + ids("setting") + ids("input"),
    "visual": ids("weather") + ids("time") + ids("look"),
    "stress": [], "chaos": [], "long": [],
}
# Linux: 105 slots by role
LINUX = [("mapgen", 6), ("explorer", 10), ("collision", 20), ("combat", 10), ("mechanic", 16), ("item", 8),
         ("ui", 6), ("stress", 8), ("chaos", 10), ("long", 6), ("visual", 5)]
assert sum(n for _, n in LINUX) == 105
# Mac: 10 slots (the Metal side: the same visual spots, gore, UI, cars)
MAC = [("visual", 2), ("combat", 2), ("mechanic", 2), ("ui", 1), ("collision", 1), ("chaos", 1), ("item", 1)]
assert sum(n for _, n in MAC) == 10

SECS = {"long": 1320, "mapgen": 1080}       # each bot stays under 30 min with startup and teardown
DEFAULT_SECS = 960
bots = []


def deal(plan, os_tag, njobs, per_job):
    slots = []
    for role, n in plan:
        for k in range(n):
            slots.append(role)
    # each role's pool is dealt round-robin over that role's bots (so every id gets a bot)
    by_role = {}
    for i, role in enumerate(slots):
        by_role.setdefault(role, []).append(i)
    assign = {i: [] for i in range(len(slots))}
    for role, idxs in by_role.items():
        pool = pools.get(role, [])
        # heavy maps first, one each
        if role == "mapgen":
            pool = sorted(pool, key=lambda s: (0 if ("supersize" in s or ":xl" in s) else 1, s))
        for j, item in enumerate(pool):
            assign[idxs[j % len(idxs)]].append(item)
    for i, role in enumerate(slots):
        job = i // per_job
        bot = f"{os_tag[0]}{job:02d}{chr(97 + i % per_job)}"
        world_seed = 42 if role in ("collision", "visual", "ui", "item", "mechanic", "combat") else (bseed(bot) % 999983)
        bots.append({"bot": bot, "os": os_tag, "job": job, "slot": i % per_job, "role": role, "seed": bseed(bot),
                     "world_seed": world_seed, "secs": SECS.get(role, DEFAULT_SECS), "assign": assign[i]})


deal(LINUX, "linux", 35, 3)
deal(MAC, "mac", 5, 2)
assigned = {a for b in bots for a in b["assign"]}
every = set()
for pool in pools.values():
    every.update(pool)
missing = sorted(every - assigned)
json.dump({"run": run, "version": cov.get("version"), "bots": bots, "unassigned": missing}, open(sys.argv[3], "w"), indent=1)
print(f"{len(bots)} bots, {len(assigned)} entries assigned, {len(missing)} unassigned")
