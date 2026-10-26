extends SceneTree
## Headless balance sweep: SurvivalBots play a fresh SimWorld for some in-game days, per skill
## and seed, with a given number of players together. tools/balance_sim.py runs one process per
## player count in parallel and prints the tables; run this directly only to debug one part.
##
## Usage: godot --headless --path game --script res://tools/balance_sim.gd -- \
##   --players=N [--days=D] [--seeds=S]
## Prints one "RUN key=value ..." line per bot and run.

## Bot skill levels: chance to dodge a telegraphed hit, and whether it backs off to heal.
const SKILLS := {
	novice = {dodge = 0.2, retreats = false},
	average = {dodge = 0.5, retreats = true},
	expert = {dodge = 0.85, retreats = true},
}
const TICK := 1.0 / 30
const ACTIVITIES := ["fight", "forage", "gather", "craft", "retreat", "wander", "dead"]

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		var args := {}
		for arg in OS.get_cmdline_user_args():
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else ""
		var players := int(args.get("players", "1"))
		var days := float(args.get("days", "3"))
		for skill: String in SKILLS:
			for s in int(args.get("seeds", "4")):
				_run(skill, players, days, 1000 + s)
		quit()
	return false


func _run(skill: String, players: int, days: float, seed_value: int) -> void:
	var t := Content.tuning
	var world := SimWorld.new()
	world.world_seed = seed_value
	world.rng.seed = seed_value
	var bots: Array[SurvivalBot] = []
	for i in players:
		world.add_player(i + 1, "bot%d" % i)
		var bot := SurvivalBot.new(world, i + 1, seed_value * 100 + i)
		bot.dodge = SKILLS[skill].dodge
		bot.retreats = SKILLS[skill].retreats
		bots.append(bot)
	var length := days * (t.day_length + t.night_length)
	for step in roundi(length / TICK):
		world.tick(TICK)
		for bot in bots:
			bot.observe(TICK)
		world.events.clear()
		for bot in bots:
			bot.act(TICK)
	var day_minutes := days * t.day_length / 60
	var night_minutes := days * t.night_length / 60
	for bot in bots:
		var inventory := bot.player().inventory
		var fields := {
			skill = skill,
			players = players,
			seed = seed_value,
			days = days,
			deaths_enemy = bot.deaths_by_enemy,
			deaths_hunger = bot.deaths_by_hunger,
			deaths_night = bot.deaths_at_night,
			kills = bot.kills,
			crowd = snappedf(bot.crowd / maxf(bot.alive, 1.0), 0.01),
			dmg_day_min = snappedf(bot.damage_day / day_minutes, 0.1),
			dmg_night_min = snappedf(bot.damage_night / night_minutes, 0.1),
			hits = bot.hits_taken,
			dodged = bot.dodged,
			starving = snappedf(bot.starving, 1),
			food_eaten = snappedf(bot.food_eaten, 1),
			lowest_health = snappedf(bot.lowest_health, 0.01),
			weapon = inventory.weapon() if inventory.weapon() != &"" else &"fists",
			armor = inventory.equipment[ItemDef.Slot.ARMOR],
		}
		for activity: String in ACTIVITIES:
			fields["t_" + activity] = snappedf(bot.time_in.get(activity, 0.0), 1)
		for item: StringName in SurvivalBot.GEAR:
			fields["at_" + item] = snappedf(bot.crafted_at.get(item, -1.0), 1)
		var line := PackedStringArray()
		for key: String in fields:
			line.append("%s=%s" % [key, fields[key]])
		print("RUN " + " ".join(line))
