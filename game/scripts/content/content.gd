class_name Content
## All game data, loaded once from res://data/ on both sides: Tuning, and items, recipes,
## enemies, dungeon rooms, buffs, synergies and building pieces by id (their file name).
## Gameplay numbers live there, not in code (PLAN §10).

static var tuning: Tuning = load("res://data/tuning.tres")
static var items := _load("res://data/items/")
static var recipes := _load("res://data/recipes/")
static var enemies := _load("res://data/enemies/")
static var rooms := _load("res://data/rooms/")
static var buffs := _load("res://data/buffs/")
static var synergies := _load("res://data/synergies/")
static var pieces := _load("res://data/pieces/")
## Item ids in a fixed order, so snapshots can send an item as its index.
static var item_ids: Array[StringName] = _sorted_ids(items)
## Enemy ids the same way, for each enemy's kind in snapshots.
static var enemy_ids: Array[StringName] = _sorted_ids(enemies)
## Buff ids the same way, for buff orbs in snapshots.
static var buff_ids: Array[StringName] = _sorted_ids(buffs)
## Building pieces the same way, also the order of the build menu.
static var piece_ids: Array[StringName] = _sorted_ids(pieces)


static func item(id: StringName) -> ItemDef:
	return items.get(id)


static func item_index(id: StringName) -> int:
	return item_ids.find(id)


static func enemy_index(def: EnemyDef) -> int:
	return enemy_ids.find(enemies.find_key(def))


static func piece(id: StringName) -> PieceDef:
	return pieces.get(id)


## The light or heavy swing of a weapon, or bare-handed for "".
static func attack(weapon: StringName, heavy: bool) -> AttackDef:
	var def := item(weapon)
	if def == null or def.slot != ItemDef.Slot.WEAPON:
		return tuning.fists_heavy if heavy else tuning.fists_light
	return def.heavy if heavy else def.light


## {id: Resource} of every resource in dir. list_directory sees through export remaps.
static func _load(dir: String) -> Dictionary:
	var out := {}
	for file in ResourceLoader.list_directory(dir):
		if file.ends_with(".tres"):
			out[StringName(file.get_basename())] = load(dir + file)
	return out


static func _sorted_ids(by_id: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(by_id.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	return ids
