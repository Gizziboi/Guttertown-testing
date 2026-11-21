#!/usr/bin/env python3
"""Merge every bot's results into one report.
  swarm_summary.py RESULTS_DIR coverage.json plan.json PREV_DIR REPORT_DIR
RESULTS_DIR holds one folder per job, each with bots/<id>/ (bot.jsonl, game.log, exit.txt, fail_NNN/, shots/).
PREV_DIR is the private repo's swarm/ folder (latest.json, baseline/), possibly empty.
Writes REPORT_DIR/REPORT.md (bugs worst first, a coverage table of every COVERAGE.md entry, what's new
since the last run, visual checks), bugs/<n>/ (the evidence of each bug), latest.json, and baseline/
updates (the first run's Linux visual shots become the known-good set). Prints PASS swarm / FAIL swarm.
"""
import json, os, sys, glob, shutil, re
from collections import defaultdict

res_dir, cov_p, plan_p, prev_dir, rep = sys.argv[1:6]
os.makedirs(rep, exist_ok=True)
cov = json.load(open(cov_p))
plan = json.load(open(plan_p))
try:
    from PIL import Image, ImageChops, ImageStat
except Exception:
    Image = None

bots = {}
for d in glob.glob(os.path.join(res_dir, "*", "bots", "*")):
    bots[os.path.basename(d)] = d
planned = {b["bot"]: b for b in plan["bots"]}

events = defaultdict(list)
for bot, d in bots.items():
    p = os.path.join(d, "bot.jsonl")
    if os.path.exists(p):
        for line in open(p, errors="replace"):
            try:
                events[bot].append(json.loads(line))
            except Exception:
                pass

SEV = {"crash": 0, "gte": 1, "script": 1, "softlock": 2, "collide": 3, "assert": 4, "visual": 5, "perf": 6}
bugs = {}           # key -> dict


def bug(kind, key, title, bot, evidence=None, extra=""):
    k = (kind, key)
    b = bugs.setdefault(k, {"kind": kind, "key": key, "title": title, "bots": [], "evidence": [], "extra": extra, "n": 0})
    b["n"] += 1
    if bot not in b["bots"]:
        b["bots"].append(bot)
    if evidence and len(b["evidence"]) < 3:
        b["evidence"].append(evidence)


covered = defaultdict(lambda: {"ok": 0, "fail": 0, "skip": 0, "why": ""})
perf = {}
for bot, evs in events.items():
    d = bots[bot]
    fails = sorted(glob.glob(os.path.join(d, "fail_*")))
    fi = 0
    fps = [e["fps"] for e in evs if e.get("k") == "perf" and e.get("fps")]
    rss = [e["rss_mb"] for e in evs if e.get("k") == "perf" and e.get("rss_mb", -1) > 0]
    perf[bot] = {"fps_min": min(fps) if fps else None, "fps_med": sorted(fps)[len(fps) // 2] if fps else None,
                 "rss_first": rss[0] if rss else None, "rss_last": rss[-1] if rss else None}
    for e in evs:
        k = e.get("k")
        if k == "assert":
            c = covered[e["id"]]
            if e["ok"]:
                c["ok"] += 1
            else:
                c["fail"] += 1
                ev = fails[fi] if fi < len(fails) else None
                fi += 1
                kind = "collide" if e["id"].startswith("collide") or "inside a solid" in e.get("what", "") else ("softlock" if e["id"] == "softlock" else "assert")
                bug(kind, e["id"] + "|" + re.sub(r"[\d.\-]+", "#", e.get("what", ""))[:90], e.get("what", ""), bot, ev)
        elif k == "cover":
            covered[e["id"]]["ok"] += 1
        elif k == "skip":
            c = covered[e["id"]]
            c["skip"] += 1
            c["why"] = e.get("why", "")
        elif k == "gte":
            ev = fails[fi] if fi < len(fails) else None
            fi += 1
            bug("gte", e.get("code", "") + "|" + e.get("text", "")[:80], f"{e.get('code')} {e.get('text')} at {e.get('where')} (during {e.get('during')})", bot, ev)
    # crashes: no "done" line, or the process ended badly
    ex = open(os.path.join(d, "exit.txt")).read().split() if os.path.exists(os.path.join(d, "exit.txt")) else ["?"]
    done = any(e.get("k") == "done" for e in evs)
    log = open(os.path.join(d, "game.log"), errors="replace").read() if os.path.exists(os.path.join(d, "game.log")) else ""
    if not done:
        last = evs[-1] if evs else {}
        why = "timed out" if ex[0] == "124" else f"exit {ex[0]}"
        tail = "\n".join(log.splitlines()[-25:])
        bug("crash", f"{why}|{last.get('during', last.get('id', ''))}", f"the game ended without finishing ({why}); last activity: {json.dumps(last)[:160]}", bot, None, tail)
    for m in re.finditer(r"SCRIPT ERROR: (.*)\n\s*at: (.*)", log):
        bug("script", m.group(1)[:90] + "|" + m.group(2)[:60], f"SCRIPT ERROR: {m.group(1)} at {m.group(2)}", bot)

# memory / fps watch
for bot, p in perf.items():
    if p["fps_min"] is not None and p["fps_min"] < 3 and planned.get(bot, {}).get("os") == "mac":
        bug("perf", "mac fps", f"fps fell to {p['fps_min']} on the Mac runner", bot)

# visual: black/flat frames, baseline diffs, Mac vs Linux
vis_notes = []
base_dir = os.path.join(prev_dir, "baseline")
new_base = os.path.join(rep, "baseline")
shots = defaultdict(dict)     # name -> os -> path
for bot, d in bots.items():
    osn = planned.get(bot, {}).get("os", "linux")
    for s in glob.glob(os.path.join(d, "shots", "*.png")):
        shots[os.path.basename(s)].setdefault(osn, s)


def diff(a, b):
    A = Image.open(a).convert("RGB").resize((480, 270))
    B = Image.open(b).convert("RGB").resize((480, 270))
    D = ImageChops.difference(A, B).convert("L")
    h = D.histogram()
    big = sum(h[48:]) / float(480 * 270)
    return big


if Image:
    for name, per in sorted(shots.items()):
        for osn, p in per.items():
            st = ImageStat.Stat(Image.open(p).convert("L"))
            if st.mean[0] < 4 or st.stddev[0] < 2:
                bug("visual", "flat:" + name, f"{name} on {osn} is a black/flat frame (mean {st.mean[0]:.1f}, sd {st.stddev[0]:.1f})", osn, p)
        if "linux" in per:
            bp = os.path.join(base_dir, name)
            if os.path.exists(bp) and name.startswith(("vis_", "weather_", "time_", "look_")):
                f = diff(per["linux"], bp)
                vis_notes.append(f"- {name}: {f*100:.1f}% of pixels differ from the known-good picture")
                if f > 0.06:
                    bug("visual", "base:" + name, f"{name} differs from the known-good picture ({f*100:.1f}% of pixels)", "linux", per["linux"])
            elif name.startswith(("vis_", "weather_", "time_", "look_")):
                os.makedirs(new_base, exist_ok=True)
                shutil.copy(per["linux"], os.path.join(new_base, name))
        if "linux" in per and "mac" in per:
            f = diff(per["linux"], per["mac"])
            vis_notes.append(f"- {name}: Mac vs Linux {f*100:.1f}% of pixels differ")
            if f > 0.12:
                bug("visual", "macvs:" + name, f"{name} renders differently on the Mac ({f*100:.1f}% of pixels)", "mac", per["mac"])

# rank and write evidence
ranked = sorted(bugs.values(), key=lambda b: (SEV.get(b["kind"], 9), -len(b["bots"]), -b["n"]))
bdir = os.path.join(rep, "bugs")
for i, b in enumerate(ranked[:60]):
    dst = os.path.join(bdir, f"{i+1:02d}")
    for j, ev in enumerate(b["evidence"]):
        if ev and os.path.isdir(ev):
            shutil.copytree(ev, os.path.join(dst, f"e{j}"), dirs_exist_ok=True)
            for jpg in glob.glob(os.path.join(dst, f"e{j}", "before_*.jpg"))[:-2]:
                os.remove(jpg)
        elif ev and os.path.isfile(ev):
            os.makedirs(dst, exist_ok=True)
            shutil.copy(ev, os.path.join(dst, os.path.basename(ev)))

prev = {}
pp = os.path.join(prev_dir, "latest.json")
if os.path.exists(pp):
    prev = json.load(open(pp))
prev_keys = set(prev.get("bug_keys", []))
cur_keys = ["%s|%s" % (b["kind"], b["key"]) for b in ranked]


def replay(bot):
    b = planned.get(bot)
    if not b:
        return bot
    return (f"`{bot}` ({b['os']}, role {b['role']}, seed {b['seed']}, world seed {b['world_seed']}): "
            f"`--scene=world --world-seed={b['world_seed']} --qa=bots/bot --role={b['role']} --bot={bot} --bot-seed={b['seed']} --assign=<its assign.json> --secs={b['secs']}`")


L = []
L.append(f"# GUTTERTOWN bot swarm, run {plan['run']} (v{plan.get('version')})\n")
nb = len(bots)
npass = sum(1 for bot in bots if any(e.get("k") == "done" and e.get("fails") == 0 for e in events[bot]))
L.append(f"{nb} of {len(planned)} bots reported; {npass} clean. {len(ranked)} distinct problems.\n")
new = [b for b in ranked if "%s|%s" % (b["kind"], b["key"]) not in prev_keys]
gone = sorted(prev_keys - set(cur_keys))
L.append("## New since the last run\n")
if not prev:
    L.append("First run: everything below is new; the Linux visual shots became the known-good set.\n")
else:
    L.append(f"{len(new)} new problems, {len(gone)} from last time not seen now.\n")
    for b in new[:20]:
        L.append(f"- **{b['kind']}** {b['title'][:200]}")
    for g in gone[:20]:
        L.append(f"- fixed or not hit: {g[:160]}")
    L.append("")
L.append("## Bugs, worst first\n")
for i, b in enumerate(ranked[:60]):
    L.append(f"### {i+1}. [{b['kind']}] {b['title'][:220]}")
    L.append(f"Seen {b['n']}x by {len(b['bots'])} bot(s). Evidence: `bugs/{i+1:02d}/` (shot.png, the frames before/after, clip.mp4).")
    L.append("Replay: " + replay(b["bots"][0]))
    if b["extra"]:
        L.append("```\n" + b["extra"][-1500:] + "\n```")
    L.append("")
L.append("## Coverage (every COVERAGE.md entry)\n")
L.append("| entry | status | ok | failed | skipped (why) |")
L.append("|---|---|---|---|---|")
tested = untested = planned_n = 0
for cat in sorted(cov["cats"]):
    for name in sorted(cov["cats"][cat]):
        cid = f"{cat}:{name}"
        status = cov["cats"][cat][name][1]
        c = covered.get(cid)
        if cat == "torture" and not c:
            c = None
        if str(status).startswith("planned"):
            planned_n += 1
            L.append(f"| `{cid}` | {status} | | | |")
            continue
        if c and (c["ok"] or c["fail"]):
            tested += 1
            L.append(f"| `{cid}` | tested | {c['ok']} | {c['fail']} | {c['skip'] or ''} |")
        else:
            untested += 1
            L.append(f"| `{cid}` | **not tested** | | | {c['why'] if c else 'no bot reached it'} |")
L.insert(2, f"Coverage: {tested} entries tested, {untested} not tested, {planned_n} planned (not built yet).\n")
L.append("\n## Performance per bot\n")
L.append("| bot | os | role | fps min | fps median | RSS first / last MB |")
L.append("|---|---|---|---|---|---|")
for bot in sorted(perf):
    b = planned.get(bot, {})
    p = perf[bot]
    L.append(f"| {bot} | {b.get('os')} | {b.get('role')} | {p['fps_min']} | {p['fps_med']} | {p['rss_first']} / {p['rss_last']} |")
if vis_notes:
    L.append("\n## Visual checks\n")
    L += vis_notes[:200]
open(os.path.join(rep, "REPORT.md"), "w").write("\n".join(L) + "\n")
json.dump({"run": plan["run"], "version": plan.get("version"), "bug_keys": cur_keys, "tested": tested, "untested": untested},
          open(os.path.join(rep, "latest.json"), "w"), indent=1)
bad = any(b["kind"] in ("crash", "gte", "script", "softlock") for b in ranked)
print("FAIL swarm" if (bad or ranked) else "PASS swarm")
