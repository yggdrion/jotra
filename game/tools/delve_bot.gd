class_name DelveBot
extends SurvivalBot
## Plays one player through a dungeon run for the balance sim: enters at the barrow, fights
## what comes near (dodging like SurvivalBot, but never backing off: nothing heals inside but a
## cleared room, so a person pushes on too), walks over buff orbs it sees,
## follows the corridors room by room, opens the end chest once the chamber is clear and leaves.
## Its run ends when it walks out or dies (dying puts it back at the entrance). It records how
## far it got.

## Enemies this close are fought: wider than SurvivalBot.ENGAGE, so it clears what keeps the
## end chest locked (Tuning.chest_lock_radius) instead of waiting beside it.
const DELVE_ENGAGE := 220.0
## Buff orbs this close are walked over.
const ORB_RANGE := 120.0
## How far into a corridor or room it aims past a doorway, so it is through it.
const STEP_IN := 8.0

var entered := false
## Walked out through the exit.
var cleared := false
var opened_chest := false
## Deepest room index reached and the rooms in its run.
var deepest := 0
var rooms := 0
## The most buff stacks and synergies it held at once.
var most_buffs := 0
var most_synergies := 0
## Sim time it entered and its run ended, -1 until then.
var entered_at := -1.0
var ended_at := -1.0


## Its run is over: it walked out or died.
func done() -> bool:
	return ended_at >= 0


func act(delta: float) -> void:
	if not _in_play(delta):
		return
	var me := player()
	most_buffs = maxi(most_buffs, _stacks())
	most_synergies = maxi(most_synergies, me.buffs.synergies().size())
	deepest = maxi(deepest, me.run.room_of(me.position))
	if _dodge():
		_spend("fight", delta)
		return
	_eat()
	var enemy := _nearest_enemy()
	var distance := enemy.position.distance_to(me.position) if enemy else INF
	if distance <= DELVE_ENGAGE:
		_spend("fight", delta)
		_fight(enemy, delta)
		return
	var orb := _nearest_orb()
	if orb:
		_spend("loot", delta)
		_walk_to(orb.position, delta)
		return
	_spend("delve", delta)
	_delve(delta)


## Enters at the start and notes when the run ended; false while there is nothing to do: not
## in yet, done, or dead.
func _in_play(delta: float) -> bool:
	var me := player()
	if done():
		return false
	if not entered:
		if world.interact(id):
			entered = true
			entered_at = world.time
			rooms = me.run.rooms.size()
		return false
	if me.run == null:
		ended_at = world.time
		return false
	if me.dead_until > 0:
		_spend("dead", delta)
		return false
	return true


## On toward the end chest and then the exit, by the corridors.
func _delve(delta: float) -> void:
	var me := player()
	var run := me.run
	var reach := Content.tuning.portal_reach
	var room := run.room_of(me.position)
	if room == run.rooms.size() - 1:
		if not opened_chest:
			if me.position.distance_to(run.chest) > reach * 0.5:
				_walk_to(run.chest, delta)
			elif world.interact(id):
				opened_chest = true
			return
		if me.position.distance_to(run.exit) > reach * 0.5:
			_walk_to(run.exit, delta)
		elif world.interact(id):
			cleared = true
			ended_at = world.time
		return
	if room >= 0:
		# The corridor leaving room i is area[i]: aim just inside its west end.
		var out := run.area[room]
		_walk_to(Vector2(out.position.x + STEP_IN, out.get_center().y), delta)
		return
	for i in run.rooms.size() - 1:
		var corridor := run.area[i]
		if Dungeon.clamp_to([corridor] as Array[Rect2], me.position) == me.position:
			_walk_to(Vector2(corridor.end.x + STEP_IN, corridor.get_center().y), delta)
			return


func _nearest_orb() -> SimWorld.SimDrop:
	var best: SimWorld.SimDrop = null
	var best_distance := ORB_RANGE
	var me := player()
	for drop: SimWorld.SimDrop in world.drops.values():
		if drop.buff == &"" or not _wants(drop.buff):
			continue
		var distance := drop.position.distance_to(me.position)
		if distance < best_distance:
			best = drop
			best_distance = distance
	return best


## Not at its max stacks yet.
func _wants(buff: StringName) -> bool:
	return player().buffs.stacks.get(buff, 0) < Content.buffs[buff].max_stacks


func _stacks() -> int:
	var total := 0
	for count: int in player().buffs.stacks.values():
		total += count
	return total


## Inside the run's rooms and corridors, sliding along the walls.
func _walk_to(target: Vector2, delta: float) -> void:
	var me := player()
	var speed := Content.tuning.walk_speed * (1.0 + me.buffs.stat("move_speed"))
	var step := me.position.move_toward(target, speed * delta)
	if me.run:
		step = Dungeon.clamp_to(me.run.area, step)
	world.move_player(id, step)
