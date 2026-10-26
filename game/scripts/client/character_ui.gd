class_name CharacterUi
extends CanvasLayer
## The character screen (C): health and armor with gear and buffs added up, the damage of a
## light and a heavy swing, what is worn and the dungeon buffs held.

var _text := Label.new()


func _ready() -> void:
	layer = 40
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_text.add_theme_font_size_override("font_size", 8)
	_text.custom_minimum_size.x = 170
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_text)
	add_child(panel)


func toggle(inventory: Inventory, buffs: Buffs, player_name: String) -> void:
	visible = not visible
	if visible:
		_text.text = describe(inventory, buffs, player_name)


## The screen's text; the stats are what the server uses (Combat.swing_damage, armor and
## health from gear and buffs).
static func describe(inventory: Inventory, buffs: Buffs, player_name: String) -> String:
	var light := Content.attack(inventory.weapon(), false)
	var heavy := Content.attack(inventory.weapon(), true)
	var lines := PackedStringArray(
		[
			player_name,
			"",
			(
				"Health %d"
				% (Content.tuning.max_health + inventory.worn("health") + buffs.stat("max_health"))
			),
			"Armor %d" % (inventory.worn("armor") + buffs.stat("armor")),
			"Light hit %d" % Combat.swing_damage(light, false, buffs),
			"Heavy hit %d" % Combat.swing_damage(heavy, true, buffs),
			"",
			"Gear",
		]
	)
	for kind: int in inventory.equipment:
		var item: StringName = inventory.equipment[kind]
		var worn := Content.item(item).display_name if item != &"" else "-"
		lines.append("  %s: %s" % [ItemDef.Slot.keys()[kind].capitalize(), worn])
	lines.append("")
	lines.append("Buffs")
	var any := false
	for id: StringName in Content.buff_ids:
		if buffs.stacks.has(id):
			var def: BuffDef = Content.buffs[id]
			lines.append("  %s x%d  %s" % [def.display_name, buffs.stacks[id], def.description])
			any = true
	for id in buffs.synergies():
		lines.append("  * %s" % Content.synergies[id].display_name)
		any = true
	if not any:
		lines.append("  none (they drop in the barrow)")
	return "\n".join(lines)
