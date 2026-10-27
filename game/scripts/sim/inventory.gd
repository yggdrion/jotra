class_name Inventory
extends RefCounted
## A player's grid of slots and their equipment. A slot is {} or {item: id, count}; stacks
## hold up to the item's max_stack. Equipment is one item id per ItemDef.Slot, "" when empty.
## changed is set on every change, for the server to resend it.

## The save and RPC key of each equipment slot.
const KEYS := {
	ItemDef.Slot.WEAPON: "weapon", ItemDef.Slot.ARMOR: "armor", ItemDef.Slot.RUNE: "rune"
}

var slots: Array[Dictionary] = []
var equipment := {ItemDef.Slot.WEAPON: &"", ItemDef.Slot.ARMOR: &"", ItemDef.Slot.RUNE: &""}
var changed := false


func _init(size: int) -> void:
	slots.resize(size)
	for i in size:
		slots[i] = {}


## Fills existing stacks first, then empty slots. Returns how many did not fit.
func add(item: StringName, count: int) -> int:
	var def := Content.item(item)
	if def == null:
		return count
	var left := count
	for pass_empty: bool in [false, true]:
		for slot in slots:
			if left == 0:
				break
			if pass_empty != slot.is_empty() or (not pass_empty and slot.item != item):
				continue
			var have: int = 0 if slot.is_empty() else slot.count
			var put := mini(def.max_stack - have, left)
			if put <= 0:
				continue
			slot.item = item
			slot.count = have + put
			left -= put
	if left != count:
		changed = true
	return left


func count_of(item: StringName) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and slot.item == item:
			total += slot.count
	return total


## Whether there is enough of everything in {item id: count}.
func has_all(items: Dictionary) -> bool:
	for item: StringName in items:
		if count_of(item) < int(items[item]):
			return false
	return true


## Takes {item id: count} out, from the last slots first. Call has_all first.
func take(items: Dictionary) -> void:
	for item: StringName in items:
		var left := int(items[item])
		for i in range(slots.size() - 1, -1, -1):
			var slot := slots[i]
			if left == 0:
				break
			if slot.is_empty() or slot.item != item:
				continue
			var used := mini(slot.count, left)
			slot.count -= used
			left -= used
			if slot.count == 0:
				slots[i] = {}
	changed = true


## Takes count out of one slot. Returns false if it holds fewer.
func take_at(index: int, count: int) -> bool:
	if not _valid(index) or slots[index].is_empty() or slots[index].count < count:
		return false
	slots[index].count -= count
	if slots[index].count == 0:
		slots[index] = {}
	changed = true
	return true


## The first slot holding food, -1 if none does.
func first_food() -> int:
	for i in slots.size():
		if not slots[i].is_empty() and Content.item(slots[i].item).food > 0:
			return i
	return -1


## Moves a slot onto another: merged if both hold the same stackable item, swapped otherwise.
func move(from: int, to: int) -> bool:
	if from == to or not _valid(from) or not _valid(to) or slots[from].is_empty():
		return false
	var a := slots[from]
	var b := slots[to]
	if not b.is_empty() and a.item == b.item:
		var put := mini(Content.item(a.item).max_stack - b.count, a.count)
		if put <= 0:
			return false
		b.count += put
		a.count -= put
		if a.count == 0:
			slots[from] = {}
	else:
		slots[from] = b
		slots[to] = a
	changed = true
	return true


## Wears the item in a slot; whatever was worn there goes into that slot.
func equip(index: int) -> bool:
	if not _valid(index) or slots[index].is_empty():
		return false
	var item: StringName = slots[index].item
	var kind := Content.item(item).slot
	if kind == ItemDef.Slot.NONE:
		return false
	var worn: StringName = equipment[kind]
	slots[index] = {} if worn == &"" else {item = worn, count = 1}
	equipment[kind] = item
	changed = true
	return true


## Takes off what is worn in an ItemDef.Slot into slot to if that is empty, else into the
## first empty one. Returns false if there is no room.
func unequip(kind: int, to := -1) -> bool:
	if equipment.get(kind, &"") == &"":
		return false
	if _valid(to) and slots[to].is_empty():
		slots[to] = {item = equipment[kind], count = 1}
	elif add(equipment[kind], 1) > 0:
		return false
	equipment[kind] = &""
	changed = true
	return true


## A separate inventory with the same contents, to try changes on.
func copy() -> Inventory:
	var out := Inventory.new(slots.size())
	out.load_data(to_data())
	return out


## The carried tool of a kind (ItemDef.Tool) with the highest tier, then damage; null if none.
func best_tool(kind: int) -> ItemDef:
	var best: ItemDef = null
	var carried: Array = slots.filter(func(slot: Dictionary) -> bool: return not slot.is_empty())
	carried = carried.map(func(slot: Dictionary) -> StringName: return slot.item)
	carried.append_array(equipment.values())
	for item: StringName in carried:
		var def := Content.item(item)
		if def == null or def.tool_kind != kind:
			continue
		if (
			best == null
			or def.tool_tier > best.tool_tier
			or (def.tool_tier == best.tool_tier and def.tool_damage > best.tool_damage)
		):
			best = def
	return best


## The first slot holding a healing draught (ItemDef.heal), -1 if none does.
func first_draught() -> int:
	for i in slots.size():
		if not slots[i].is_empty() and Content.item(slots[i].item).heal > 0:
			return i
	return -1


## The ability the worn rune grants, null if none.
func ability() -> AbilityDef:
	var rune := Content.item(equipment[ItemDef.Slot.RUNE])
	return Content.abilities.get(rune.ability) if rune else null


func weapon() -> StringName:
	return equipment[ItemDef.Slot.WEAPON]


## Sum of a stat ("armor", "health") over everything worn.
func worn(stat: String) -> float:
	var total := 0.0
	for item: StringName in equipment.values():
		if item != &"":
			total += Content.item(item).get(stat)
	return total


## Plain arrays and strings, for JSON saves and RPCs: {slots: [[id, count] or []], weapon,
## armor, rune}.
func to_data() -> Dictionary:
	var out := []
	for slot in slots:
		out.append([] if slot.is_empty() else [str(slot.item), slot.count])
	var data := {slots = out}
	for kind: int in KEYS:
		data[KEYS[kind]] = str(equipment[kind])
	return data


## The reverse of to_data. Items this build doesn't know any more are dropped.
func load_data(data: Dictionary) -> void:
	var saved: Array = data.get("slots", [])
	for i in slots.size():
		var entry: Array = saved[i] if i < saved.size() else []
		var known := entry.size() == 2 and Content.item(entry[0]) != null
		slots[i] = {item = StringName(entry[0]), count = int(entry[1])} if known else {}
	for kind: int in equipment:
		var item := StringName(data.get(KEYS[kind], ""))
		var def := Content.item(item)
		equipment[kind] = item if def != null and def.slot == kind else &""
	changed = true


func _valid(index: int) -> bool:
	return index >= 0 and index < slots.size()
