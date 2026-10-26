class_name Inventory
extends RefCounted
## A player's grid of slots and their equipment. A slot is {} or {item: id, count}; stacks
## hold up to the item's max_stack. Equipment is one item id per ItemDef.Slot, "" when empty.
## changed is set on every change, for the server to resend it.

var slots: Array[Dictionary] = []
var equipment := {ItemDef.Slot.WEAPON: &"", ItemDef.Slot.ARMOR: &""}
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


## Takes off what is worn in an ItemDef.Slot, if there is room for it.
func unequip(kind: int) -> bool:
	if equipment.get(kind, &"") == &"":
		return false
	if add(equipment[kind], 1) > 0:
		return false
	equipment[kind] = &""
	changed = true
	return true


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
## armor}.
func to_data() -> Dictionary:
	var out := []
	for slot in slots:
		out.append([] if slot.is_empty() else [str(slot.item), slot.count])
	return {
		slots = out,
		weapon = str(equipment[ItemDef.Slot.WEAPON]),
		armor = str(equipment[ItemDef.Slot.ARMOR]),
	}


## The reverse of to_data. Items this build doesn't know any more are dropped.
func load_data(data: Dictionary) -> void:
	var saved: Array = data.get("slots", [])
	for i in slots.size():
		var entry: Array = saved[i] if i < saved.size() else []
		var known := entry.size() == 2 and Content.item(entry[0]) != null
		slots[i] = {item = StringName(entry[0]), count = int(entry[1])} if known else {}
	for kind: int in equipment:
		var key := "weapon" if kind == ItemDef.Slot.WEAPON else "armor"
		var item := StringName(data.get(key, ""))
		var def := Content.item(item)
		equipment[kind] = item if def != null and def.slot == kind else &""
	changed = true


func _valid(index: int) -> bool:
	return index >= 0 and index < slots.size()
