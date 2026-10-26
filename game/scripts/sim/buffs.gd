class_name Buffs
extends RefCounted
## The dungeon buffs a player holds, {buff id: stacks}, and the stats they and the synergies
## between them (SynergyDef) add up to. Shared by the server (SimPlayer.buffs) and the client,
## which predicts its own walk speed and swing cooldowns from them. changed is set on every
## change, for the server to resend it.

## What a buff can raise. Shares (damage, heavy_damage, attack_speed, crit, stamina_regen,
## move_speed, lifesteal) are fractions; the rest are flat: health, armor, seconds (iframes),
## damage a second (bleed, for Tuning.bleed_time), health or stamina per kill, damage.
const STATS: Array[String] = [
	"damage",
	"heavy_damage",
	"attack_speed",
	"crit",
	"max_health",
	"armor",
	"stamina_regen",
	"move_speed",
	"iframes",
	"lifesteal",
	"bleed",
	"kill_heal",
	"kill_stamina",
	"dash_damage",
	"thorns",
]

var stacks := {}
var changed := false


## One more stack of a buff, unless it is unknown or at its max_stacks. Returns whether it took.
func add(id: StringName) -> bool:
	var def: BuffDef = Content.buffs.get(id)
	if def == null or stacks.get(id, 0) >= def.max_stacks:
		return false
	stacks[id] = stacks.get(id, 0) + 1
	changed = true
	return true


func clear() -> void:
	if not stacks.is_empty():
		stacks = {}
		changed = true


## The sum of a stat over all stacks and the synergies held.
func stat(name: String) -> float:
	var total := 0.0
	for id: StringName in stacks:
		var def: BuffDef = Content.buffs[id]
		if def.stat == name:
			total += def.amount * stacks[id]
	for id in synergies():
		var synergy: SynergyDef = Content.synergies[id]
		if synergy.stat == name:
			total += synergy.amount
	return total


## Ids of the synergies whose buffs are all held.
func synergies() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in Content.synergies:
		var synergy: SynergyDef = Content.synergies[id]
		if synergy.buffs.all(func(buff: StringName) -> bool: return stacks.has(buff)):
			out.append(id)
	return out


## {buff id: stacks} with plain string keys, for RPCs.
func to_data() -> Dictionary:
	var out := {}
	for id: StringName in stacks:
		out[str(id)] = stacks[id]
	return out


## The reverse of to_data; unknown buffs are dropped.
func load_data(data: Dictionary) -> void:
	stacks = {}
	for key: String in data:
		if Content.buffs.has(StringName(key)):
			stacks[StringName(key)] = int(data[key])
	changed = true


## A random buff id: a rarity by Tuning.buff_rarity_weights, the rarer ones weighted up by
## rare_bonus (0: as is), then any buff of that rarity.
static func roll(rng: RandomNumberGenerator, rare_bonus := 0.0) -> StringName:
	var weights: Array[float] = []
	for i in Content.tuning.buff_rarity_weights.size():
		weights.append(Content.tuning.buff_rarity_weights[i] * (1.0 + rare_bonus * i))
	var rarity := rng.rand_weighted(PackedFloat32Array(weights))
	var choices: Array[StringName] = []
	for id: StringName in Content.buff_ids:
		if Content.buffs[id].rarity == rarity:
			choices.append(id)
	if choices.is_empty():
		return Content.buff_ids[rng.randi() % Content.buff_ids.size()]
	return choices[rng.randi() % choices.size()]
