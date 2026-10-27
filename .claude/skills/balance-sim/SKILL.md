---
name: balance-sim
description: Simulate Jotra headless with bots of three skill levels (solo and in groups of 2 and 4) for in-game days or dungeon runs, to judge difficulty and balance without playing. Use when asked whether the game or the dungeon is too easy or hard, wants balance numbers, or before and after changing any gameplay number in game/data (enemies, weapons, armor, recipes, drops, hunger, day/night, scaling, rooms, buffs).
---

# Balance sim

`python tools/balance_sim.py` runs `game/tools/balance_sim.gd` in one headless Godot process per group size, in parallel, and prints the tables. Each player is a `SurvivalBot` (`game/tools/survival_bot.gd`) driving a plain `SimWorld` through the same calls the server makes for a client, at the server's 30 Hz tick. The bot eats below half hunger, forages trees while carrying less than 40 hunger of food, gathers wood and stone for the next gear upgrade, crafts it (walking to the workbench) and wears it, fights enemies within 150 px and otherwise wanders.

Skill levels (`SKILLS` in `balance_sim.gd`):

| skill | dashes out of a telegraphed hit | backs off when low |
|---|---|---|
| novice | 20% | never: fights everything to the end |
| average | 50% | below 35% health, until 60% |
| expert | 85% | same |

## Run it

    python tools/balance_sim.py --quick --players 1   # ~1 min: solo, 3 seeds, 2 days. Use while tuning
    python tools/balance_sim.py --quick               # ~3 min: also groups of 2 and 4
    python tools/balance_sim.py --csv build/balance.csv   # ~6 min: 6 seeds, 3 days, every group size

Run the full one in the background. One in-game day is `day_length + night_length` (12 minutes).

## Read it

- **Danger:** deaths per bot per in-game day (and how many starved, how many at night), damage taken per minute by day and by night, the lowest health it ever had, kills, and enemies within 150 px on average.
- **Hunger:** seconds per day spent starving, hunger eaten per day.
- **Time spent:** share of play per activity. Forage is gathering for food, gather for gear, retreat is backing off at low health.
- **Gear:** how many bots crafted each piece and the median time, in minutes.
- The bot plays worse than a person (no kiting, no focus fire in groups, groups of identical bots stand in one blob) and better in places (it never forgets to eat). Compare skills, group sizes and before/after; don't read the numbers as what a player will see. All-novice groups come out much harder than solo mostly because of the blobbing.

## Targets (set 2026-10-26: "game shouldn't be easy")

| | target |
|---|---|
| novice, solo | 2–4 deaths per day: fighting everything to the end gets punished |
| average, solo | 0.2–1 deaths per day, mostly at night |
| expert, solo | ≤ 0.3 deaths per day, but close calls: lowest health under 40% |
| day vs night | real damage by day; night clearly more (novice ~2×) |
| hunger | foraging ≥ 7% of play time; starving deaths only when something else went wrong |
| gear | bone sword and bone armor not before the end of day 1 (12 min) |
| groups | average and expert deaths per player within ~3× solo; novice groups may be harder |

## Tune with it

1. Run `--quick --players 1` on main as the baseline and keep the output.
2. Change one number in `game/data/` (`tuning.tres`, `enemies/`, `items/`, `recipes/`).
3. Run it again and compare. To try several values at once, copy `game/` into the scratchpad once per value and run `balance_sim.gd` against each copy with `--path`.
4. When solo looks right, run `--quick` for the groups, then the full run to confirm.
5. Run `python tools/check.py` (tests that hard-code numbers break: read them from `Content` instead) and put the full-run table in the commit or PR.
6. Update "Last full result" below.

Levers that mattered in the first tuning (2026-10-26):

- Health regen against damage taken per minute: when regen matches it, a short break heals fully and nobody dies.
- Enemy speed against `walk_speed`, and `windup_speed`: if a player can outwalk a draugr or walk out of its windup, backing off is always safe. Now only a dash dodges, and at night (`night_speed`) draugr outrun a walking player.
- `gather_time`: without it E removes a prop per frame and gathering costs nothing.
- Self-scaling: extra enemy health lets enemies live longer than a group without focus fire can kill them. Scale count rather than health.

## Last full result (2026-10-26, co-op scaling count 0.3, health 0.15, damage 0)

Deaths per day (novice / average / expert): solo 3.83 / 0.22 / 0.06, groups of 2 5.19 / 0.39 / 0.06, groups of 4 7.12 / 0.58 / 0.15. Groups stay a bit harder per player than solo, within ~3×. Night damage per minute about 2× day for novices and experts, 1.4× for average bots (they back off). Foraging 6–22% of play, nobody starves for long. Bone sword median 10–14 min solo, bone armor 13–22 min. Off target: novice groups get their gear fast (4–7 min) from the many kills.

Co-op scaling sweep (groups of 4, 2 days, 6 seeds; average bot deaths/day): count/health/damage 0.5/0.15/0.1 → 0.96, 0.3/0.15/0 → 0.54, 0.3/0/0 → 0.58, 0.15/0.3/0 → 0.71. Damage scaling was what hurt groups most.

## Dungeon runs (`--dungeon`)

`python tools/balance_sim.py --dungeon [--quick] [--players 1]` puts `DelveBot`s (`game/tools/delve_bot.gd`, a `SurvivalBot` that dodges the same way) at the barrow with one of three gear tiers and 5 trail rations, and they take one run together: fight what comes within 220 px, walk over buff orbs, follow the corridors, open the end chest, leave. They never back off inside (nothing heals but a cleared room). A run ends when a bot walks out or dies; 20 minutes counts as stuck. Tiers: `fresh` (nothing), `crafted` (club, cloth tunic), `best` (bone sword, bone armor). `--quick` is 8 seeds (~1 min per group size), the default 20.

Columns: cleared, died and stuck as shares; chest opened; boss (the barrow king) seen dying; deepest room reached of the rooms after the start; the median room deaths happened in; median minutes to clear; most buff stacks held at once; kills; lowest health.

The bot clears much faster than a person (1–2 min: no hesitating, no looking around). It dashes as a telegraph ends (`REACT` at the earliest), so the i-frames cover the slam's long windup too; since then skill matters inside (expert dodges 85%).

To try several values at once, copy `game/` into the scratchpad once per value (symlink `addons/`), edit `data/tuning.tres` or `data/rooms/*.tres` in each copy, and run `balance_sim.gd -- --players=N --seeds=S --dungeon` against each with `--path`, in parallel.

### Targets (set 2026-10-26)

| | target |
|---|---|
| fresh gear | never clears: the barrow is not for a new player |
| crafted gear, solo | rarely or never clears; a group of 4 sometimes does |
| best gear, solo | clears most runs (60–90%), but with close calls: lowest health under 35% |
| deaths | in the deeper rooms (median room of death ≥ 3 with best gear), not at the door |
| groups | clear at least as often as solo; may be easier, but not a walk (lowest health under ~75%) |
| boss | the barrow king is what kills best-gear solo runs that die: deaths in the end room |

### Levers that mattered (2026-10-26)

- Spawns per room (`game/data/rooms/*.tres`): 3–4 draugr waking at once killed every bot by room 3–4 whatever its gear; 2–3 per room is what best gear can take.
- `room_clear_heal`: without healing inside, every run was a war of attrition nobody won. 0.3 vs 0.6 changes less than spawns or depth scaling.
- `depth_damage` against `depth_health`: damage per room decides whether the last rooms kill; 0.1 → 0.075 took best-gear solo clears from ~25% to ~80%.
- The boss (2026-10-26): on top of the end room's draugr even 200 hp killed nearly every bot; the end room is now the boss alone. With the old dodge timing (dash 0.2 s in) no bot survived a 1.1 s slam. 300 → 350 health at 16 damage took best-gear solo clears (all skills) from 79% to 62%.
- `room_count` / `room_health`: the overworld's group scaling (count 0.3) let groups of 4 clear with 90%+ health left; rooms scale on their own, count 1.0 and health 0.25 per extra player. Still easier in groups: four bone swords on one room kill it fast.

### Last full dungeon result (2026-10-26, 20 seeds; rooms of 2–3 spawns, room_clear_heal 0.4, depth health/damage 0.15/0.075, room count/health 1.0/0.25; barrow king 325 hp, 16 damage, alone in the end room; bots dodge at the telegraph's end)

Cleared (novice / average / expert): fresh gear 0% but 1–10% for average/expert groups; crafted solo 0 / 0 / 15%, groups of 2 2 / 12 / 55%, groups of 4 45 / 74 / 72%; best solo 35 / 70 / 100% with lowest health 7 / 18 / 50%, groups of 2 98–100% (lowest 47–75%), groups of 4 100% (lowest 71–85%). Every clear killed the boss; best-gear deaths happen in rooms 6–7. Off target: expert solo with best gear has no close calls, crafted groups of 4 clear more than "sometimes" and groups of 4 are a walk; all three came with the better dodge timing, not the boss (re-tune depth damage and group scaling next).

## After M16 (2026-10-27, `--quick`: 3 seeds, 2 days; day mix draugr/wolves, night adds archers, shields, exploders; bots dodge archer lines by sidestepping, flank shields, wear hide armor)

Baseline before (solo, same settings): deaths/day novice 2.67, average 0.50, expert 0.17. After, deaths per day (novice / average / expert): solo 4.00 / 0.33 / 0.33, groups of 2 5.92 / 0.58 / 0.25, groups of 4 12.54 / 1.83 / 0.67. Solo is within the targets (expert a little over 0.3, lowest health 11%); average groups of 4 are ~5× solo, over the ~3× target (it was already over before M16). Damage per minute by night is 2–4× by day for novices. Kills per day roughly doubled (wolf packs). Hide armor (14 hide) comes at 5–15 min, bone armor still after 12 min. Wolf meat is 0.15 a kill: at 0.3–0.8 bots stopped foraging (2–4% of play) because meat fed them. Three seeds are noisy (a solo novice swung 2.5–4.5 deaths/day between runs with only drop tweaks), so rerun with more seeds before tuning on it.
