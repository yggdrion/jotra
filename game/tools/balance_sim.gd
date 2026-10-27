extends SceneTree
## Headless balance sweep: SurvivalBots play a fresh SimWorld for some in-game days, per skill
## and seed, with a given number of players together. tools/balance_sim.py runs one process per
## player count in parallel and prints the tables; run this directly only to debug one part.
##
## Usage: godot --headless --path game --script res://tools/balance_sim.gd -- \
##   --players=N [--days=D] [--seeds=S] [--dungeon]
## Prints one "RUN key=value ..." line per bot and run. With --dungeon, DelveBots take one
## dungeon run together instead, per skill, gear tier and seed, and print "DELVE ..." lines.

## Bot skill levels: chance to dodge a telegraphed hit, the share of those dodges timed inside
## the perfect window, and whether it backs off to heal.
const SKILLS := {
	novice = {dodge = 0.2, perfect = 0.0, retreats = false},
	average = {dodge = 0.5, perfect = 0.25, retreats = true},
	expert = {dodge = 0.85, perfect = 0.6, retreats = true},
}
const TICK := 1.0 / 30
const ACTIVITIES := ["fight", "forage", "gather", "craft", "retreat", "grave", "wander", "dead"]
## What a DelveBot carries into the dungeon: nothing, the first crafted gear, the best.
const TIERS := {
	fresh = [],
	crafted = [&"club", &"cloth_tunic"],
	best = [&"bone_sword", &"bone_armor"],
}
## Runes the best-geared DelveBots wear, one each in turn by seed and player.
const RUNES: Array[StringName] = [&"frost_rune", &"ward_rune", &"shock_rune"]
## Trail rations each DelveBot brings.
const RATIONS := 5
## A dungeon run that takes longer than this counts as stuck.
const DELVE_LIMIT := 1200.0

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
				if args.has("dungeon"):
					for tier: String in TIERS:
						_delve(skill, tier, players, 1000 + s)
				else:
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
		_set_skill(bot, skill)
		bots.append(bot)
	for bot in bots:
		bot.group = bots
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
			perfect = bot.perfects,
			drunk = bot.drunk,
			abilities = bot.abilities,
			stewed = bot.stewed,
			rune = _rune(bot),
			starving = snappedf(bot.starving, 1),
			food_eaten = snappedf(bot.food_eaten, 1),
			lowest_health = snappedf(bot.lowest_health, 0.01),
			graves_left = bot.player().graves.size(),
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


func _delve(skill: String, tier: String, players: int, seed_value: int) -> void:
	var world := SimWorld.new()
	world.world_seed = seed_value
	world.rng.seed = seed_value
	world.spawn_enemies = false
	var bots: Array[DelveBot] = []
	for i in players:
		var player := world.add_player(i + 1, "bot%d" % i)
		player.position = Content.tuning.dungeon_entrance + Vector2(i * 4, 0)
		var gear: Array = TIERS[tier].duplicate()
		if tier == "best":
			gear.append(RUNES[(seed_value + i) % RUNES.size()])
		for item: StringName in gear:
			player.inventory.add(item, 1)
			player.equip(player.inventory.slots.find({item = item, count = 1}))
		player.health = player.max_health()
		player.inventory.add(&"trail_ration", RATIONS)
		var bot := DelveBot.new(world, i + 1, seed_value * 100 + i)
		_set_skill(bot, skill)
		bots.append(bot)
	for bot in bots:
		bot.group = bots
	var steps := 0
	while (
		steps < roundi(DELVE_LIMIT / TICK)
		and not bots.all(func(b: DelveBot) -> bool: return b.done())
	):
		world.tick(TICK)
		for bot in bots:
			bot.observe(TICK)
		world.events.clear()
		for bot in bots:
			bot.act(TICK)
		steps += 1
	for bot in bots:
		var end := bot.ended_at if bot.done() else world.time
		var fields := {
			skill = skill,
			players = players,
			tier = tier,
			seed = seed_value,
			cleared = int(bot.cleared),
			died = int(bot.deaths_by_enemy + bot.deaths_by_hunger > 0),
			stuck = int(not bot.done()),
			chest = int(bot.opened_chest),
			boss = int(bot.boss_down),
			deepest = bot.deepest,
			rooms = bot.rooms,
			minutes = snappedf((end - bot.entered_at) / 60.0, 0.1),
			kills = bot.kills,
			buffs = bot.most_buffs,
			synergies = bot.most_synergies,
			lowest_health = snappedf(bot.lowest_health, 0.01),
			hits = bot.hits_taken,
			dodged = bot.dodged,
			perfect = bot.perfects,
			drunk = bot.drunk,
			abilities = bot.abilities,
		}
		var line := PackedStringArray()
		for key: String in fields:
			line.append("%s=%s" % [key, fields[key]])
		print("DELVE " + " ".join(line))


func _set_skill(bot: SurvivalBot, skill: String) -> void:
	bot.dodge = SKILLS[skill].dodge
	bot.perfect = SKILLS[skill].perfect
	bot.retreats = SKILLS[skill].retreats


## The rune it wears at the end, or none.
func _rune(bot: SurvivalBot) -> StringName:
	var rune: StringName = bot.player().inventory.equipment[ItemDef.Slot.RUNE]
	return rune if rune != &"" else &"none"
