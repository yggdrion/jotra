"""Headless balance sweep with SurvivalBot (game/tools/balance_sim.gd).

Bots play fresh worlds for some in-game days at three skill levels (how often they dash out
of a telegraphed hit, whether they back off to heal), solo and in groups, and the tables show
deaths, damage by day and night, hunger, how they spent their time and how fast they got gear.
The bot plays worse than a person in some ways (no kiting) and better in others (perfect
eating): compare skills, group sizes and before/after, don't read the numbers as a player's.

With --dungeon, DelveBots instead take one dungeon run together per skill, gear tier (fresh,
crafted, best) and seed, and the table shows how many cleared it, died or got stuck, how deep
they got, how long it took and how many buffs they held.

Usage: python tools/balance_sim.py [--quick] [--days D] [--players 1,2,4] [--dungeon] [--csv FILE]
  --quick   3 seeds and 2 days instead of 6 and 3 (~2 min instead of ~5); dungeon: 8 seeds, not 20
  --dungeon dungeon runs instead of overworld days
  --players only these group sizes (default 1,2,4), e.g. 1 for a fast solo check
  --csv     also write every bot run as CSV
Set GODOT_BIN to use your own binary; it must match .godot-version.
"""

import argparse
import statistics
import subprocess

from _common import GAME, fail, godot, godot_import

SKILLS = ["novice", "average", "expert"]
ACTIVITIES = ["fight", "forage", "gather", "craft", "retreat", "wander", "dead"]

parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
parser.add_argument("--quick", action="store_true")
parser.add_argument("--days", type=float)
parser.add_argument("--players", default="1,2,4")
parser.add_argument("--dungeon", action="store_true")
parser.add_argument("--csv")
args = parser.parse_args()
days = args.days or (2 if args.quick else 3)
seeds = 3 if args.quick else 6
if args.dungeon:
    seeds = 8 if args.quick else 20
TIERS = ["fresh", "crafted", "best"]
TAG = "DELVE " if args.dungeon else "RUN "
GROUPS = [int(n) for n in args.players.split(",")]

godot_bin = godot()
godot_import(godot_bin)
procs = [
    subprocess.Popen(
        [godot_bin, "--headless", "--path", ".", "--script", "res://tools/balance_sim.gd", "--",
         f"--players={n}", f"--days={days}", f"--seeds={seeds}", *(["--dungeon"] if args.dungeon else [])],
        cwd=GAME,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    for n in GROUPS
]
runs = []
for n, proc in zip(GROUPS, procs):
    out, _ = proc.communicate()
    rows = [line[len(TAG):].split() for line in out.splitlines() if line.startswith(TAG)]
    if proc.returncode != 0 or not rows:
        fail(f"balance_sim.gd --players={n} printed no results (exit {proc.returncode})")
    for fields in rows:
        row = dict(field.split("=", 1) for field in fields)
        for key, value in row.items():
            try:
                row[key] = float(value)
            except ValueError:
                pass
        runs.append(row)


def mean(rows, key):
    return statistics.mean(r[key] for r in rows)


def show(title, columns, among=None):
    """columns: [(header, function of rows -> str)], one line per skill and group size."""
    print(f"\n{title}")
    print("skill   players" + "".join(h.rjust(15) for h, _ in columns))
    for skill in SKILLS:
        for n in GROUPS:
            rows = [r for r in (among or runs) if r["skill"] == skill and r["players"] == n]
            if rows:
                print(f"{skill:8}{n:7d}" + "".join(f(rows).rjust(15) for _, f in columns))


def per_day(key):
    return lambda rows: f"{mean(rows, key) / days:.2f}"


def deaths(rows):
    return sum(r["deaths_enemy"] + r["deaths_hunger"] for r in rows)


def night_share(rows):
    total = deaths(rows)
    return f"{100 * sum(r['deaths_night'] for r in rows) / total:.0f}%" if total else "-"


def reached(item):
    def cell(rows):
        times = [r[f"at_{item}"] for r in rows if r[f"at_{item}"] >= 0]
        if not times:
            return "never"
        return f"{len(times)}/{len(rows)} {statistics.median(times) / 60:.0f}m"

    return cell


def write_csv():
    if args.csv:
        keys = list(runs[0].keys())
        with open(args.csv, "w", encoding="utf-8") as out:
            out.write(",".join(keys) + "\n")
            for r in runs:
                out.write(",".join(str(r[k]) for k in keys) + "\n")
        print(f"\n{len(runs)} bot runs written to {args.csv}")


def share(key):
    return lambda rows: f"{100 * mean(rows, key):.0f}%"


def cleared_minutes(rows):
    times = [r["minutes"] for r in rows if r["cleared"]]
    return f"{statistics.median(times):.1f}" if times else "-"


def died_deepest(rows):
    deaths = [r["deepest"] for r in rows if r["died"]]
    return f"{statistics.median(deaths):.0f}" if deaths else "-"


if args.dungeon:
    print(f"Dungeon runs, {seeds} seeds per skill and tier; per bot")
    for tier in TIERS:
        print(f"\n== Gear: {tier}")
        show("Dungeon", [
            ("cleared", share("cleared")),
            ("died", share("died")),
            ("stuck", share("stuck")),
            ("chest", share("chest")),
            ("boss", share("boss")),
            ("deepest", lambda rows: f"{mean(rows, 'deepest'):.1f}/{mean(rows, 'rooms') - 1:.1f}"),
            ("died in room", died_deepest),
            ("clear min", cleared_minutes),
            ("buffs", lambda rows: f"{mean(rows, 'buffs'):.1f}"),
            ("kills", lambda rows: f"{mean(rows, 'kills'):.1f}"),
            ("lowest hp", lambda rows: f"{100 * mean(rows, 'lowest_health'):.0f}%"),
        ], [r for r in runs if r["tier"] == tier])
    write_csv()
    raise SystemExit(0)

print(f"{days:g} in-game days, {seeds} seeds; per bot, averaged over its runs")
show("Danger", [
    ("deaths/day", lambda rows: f"{(deaths(rows)) / len(rows) / days:.2f}"),
    ("starved/day", per_day("deaths_hunger")),
    ("at night", night_share),
    ("dmg/min day", lambda rows: f"{mean(rows, 'dmg_day_min'):.1f}"),
    ("dmg/min night", lambda rows: f"{mean(rows, 'dmg_night_min'):.1f}"),
    ("lowest hp", lambda rows: f"{100 * mean(rows, 'lowest_health'):.0f}%"),
    ("kills/day", per_day("kills")),
    ("enemies near", lambda rows: f"{mean(rows, 'crowd'):.2f}"),
])
show("Hunger", [
    ("starving s/day", per_day("starving")),
    ("eaten/day", per_day("food_eaten")),
])
show("Time spent (% of play)", [
    (a, lambda rows, a=a: f"{100 * sum(r['t_' + a] for r in rows) / sum(sum(r['t_' + x] for x in ACTIVITIES) for r in rows):.0f}%")
    for a in ACTIVITIES
])
show("Gear crafted (bots that got it, median time)", [
    (item, reached(item)) for item in ["club", "stone_axe", "cloth_tunic", "bone_armor", "bone_sword"]
])
write_csv()
