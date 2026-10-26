class_name InventoryUi
extends CanvasLayer
## The inventory screen (Tab or I), in three columns: what is worn and its stats above the
## backpack grid; an info panel on whatever the mouse is over; and the recipes, each with what
## it needs against what the player has and, if it can't be crafted, why. Items are dragged to
## move, stack, wear or take off; right click wears or takes off at once. A line at the bottom
## says so. Everything is only a request: the server's inventory comes back through
## show_inventory.

signal move_requested(from: int, to: int)
signal equip_requested(index: int)
signal unequip_requested(kind: int, to: int)
signal craft_requested(recipe: StringName)

const SLOT := 20
const COLUMNS := 6
const FONT_SIZE := 8
const DIM := Color(1, 1, 1, 0.35)
const HEADING := Color("feae34")
const OK := Color("63c74d")
const BAD := Color("e43b44")
const INFO_WIDTH := 120
const CONTROLS := "Drag: move, stack, wear   Right click: wear or take off   Tab: close"
const STATUS_TEXT := {
	Crafting.Status.READY: "",
	Crafting.Status.MISSING_ITEMS: "Missing items",
	Crafting.Status.NO_ROOM: "No room for it",
}


## One slot: the item as a square in its color, outlined in its rarity's, with the count.
## index is its backpack slot, or -1 for an equipment slot of kind worn.
class SlotView:
	extends Control

	var item: StringName
	var count := 0
	var index := -1
	var worn := -1
	## Shown while empty, e.g. "W" for the weapon slot.
	var hint := ""
	var ui: InventoryUi
	var _drop_ok := false

	func _init() -> void:
		custom_minimum_size = Vector2(InventoryUi.SLOT, InventoryUi.SLOT)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_exited.connect(func() -> void: _set_drop_ok(false))

	func show_item(id: StringName, amount: int) -> void:
		item = id
		count = amount
		queue_redraw()

	func _get_drag_data(_at: Vector2) -> Variant:
		if Content.item(item) == null or ui == null:
			return null
		var preview := SlotView.new()
		preview.show_item(item, count)
		preview.modulate.a = 0.8
		var holder := Control.new()  # centers the preview on the mouse
		holder.add_child(preview)
		preview.position = -preview.custom_minimum_size / 2
		set_drag_preview(holder)
		return {from = index, worn = worn}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok := ui != null and data is Dictionary and ui.can_drop(data, self)
		_set_drop_ok(ok)
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_set_drop_ok(false)
		ui.drop(data, self)

	func _set_drop_ok(value: bool) -> void:
		if value != _drop_ok:
			_drop_ok = value
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE if _drop_ok else InventoryUi.DIM, false, 1)
		var font := get_theme_default_font()
		var def := Content.item(item)
		if def == null:
			var center := HORIZONTAL_ALIGNMENT_CENTER
			draw_string(
				font, Vector2(0, 13), hint, center, size.x, InventoryUi.FONT_SIZE, InventoryUi.DIM
			)
			return
		var icon := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		draw_rect(icon, def.color)
		draw_rect(icon, ItemDef.RARITY_COLORS[def.rarity], false, 1)
		if count > 1:
			var at := Vector2(0, size.y - 1)
			var right := HORIZONTAL_ALIGNMENT_RIGHT
			var font_size := InventoryUi.FONT_SIZE
			draw_string_outline(font, at, str(count), right, size.x - 1, font_size, 2, Color.BLACK)
			draw_string(font, at, str(count), right, size.x - 1, font_size)


## The player's position, set by GameClient every frame, for the station checks.
var player_at := Vector2.ZERO

var _inventory := Inventory.new(Content.tuning.inventory_size)
var _panel := PanelContainer.new()
var _slots: Array[SlotView] = []
var _worn := {}  # ItemDef.Slot -> SlotView
var _stats := Label.new()
var _info_title := Label.new()
var _info_body := Label.new()
## recipe id -> {inputs: {item id: Label}, status: Label, button: Button}
var _recipes := {}
## Last shown Crafting.Status per recipe, to redraw only on change.
var _statuses := {}


## What an item is, its stats, where it comes from and what it is for, for the info panel.
static func describe(id: StringName) -> String:
	var def := Content.item(id)
	if def == null:
		return ""
	var lines := PackedStringArray([ItemDef.Rarity.keys()[def.rarity].capitalize()])
	match def.slot:
		ItemDef.Slot.WEAPON:
			lines[0] += " weapon"
			lines.append("Light hit %d, heavy hit %d" % [def.light.damage, def.heavy.damage])
		ItemDef.Slot.ARMOR:
			lines[0] += " armor"
			lines.append("Blocks %d damage per hit" % def.armor)
			lines.append("Max health +%d" % def.health)
		_:
			lines[0] += " material"
	var found := sources(id)
	if not found.is_empty():
		lines.append("From: " + ", ".join(found))
	var uses := used_in(id)
	if not uses.is_empty():
		lines.append("For: " + ", ".join(uses))
	return "\n".join(lines)


## Where an item drops: "trees", "rocks", enemy names, "crafting".
static func sources(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var tables := {trees = Content.tuning.tree_drops, rocks = Content.tuning.rock_drops}
	for enemy: StringName in Content.enemies:
		tables[str(enemy).capitalize().to_lower()] = Content.enemies[enemy].drops
	for source: String in tables:
		if tables[source].any(func(e: Dictionary) -> bool: return StringName(e.item) == id):
			out.append(source)
	for recipe: RecipeDef in Content.recipes.values():
		if recipe.result == id:
			out.append("crafting")
			break
	return out


## Names of what an item is crafted into.
static func used_in(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for recipe: RecipeDef in Content.recipes.values():
		if recipe.inputs.has(id):
			out.append(Content.item(recipe.result).display_name)
	return out


func _ready() -> void:
	visible = false
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	_panel.theme = theme
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	rows.add_child(columns)
	columns.add_child(_build_inventory())
	columns.add_child(_build_info())
	columns.add_child(_build_crafting())
	var controls := _label(CONTROLS, DIM)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(controls)
	_show_info(&"")
	_refresh()


func _build_inventory() -> Control:
	var column := VBoxContainer.new()
	column.add_child(_label("Equipped", HEADING))
	var worn := HBoxContainer.new()
	column.add_child(worn)
	for kind: int in [ItemDef.Slot.WEAPON, ItemDef.Slot.ARMOR]:
		var view := _slot_view()
		view.worn = kind
		view.hint = "W" if kind == ItemDef.Slot.WEAPON else "A"
		worn.add_child(view)
		_worn[kind] = view
	_stats.custom_minimum_size.x = COLUMNS * (SLOT + 4)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	worn.add_child(_stats)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_label("Backpack", HEADING))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	column.add_child(grid)
	for i in _inventory.slots.size():
		var view := _slot_view()
		view.index = i
		grid.add_child(view)
		_slots.append(view)
	return column


func _build_info() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = INFO_WIDTH
	_info_title.add_theme_color_override("font_color", HEADING)
	column.add_child(_info_title)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_body.custom_minimum_size.x = INFO_WIDTH
	column.add_child(_info_body)
	return column


func _build_crafting() -> Control:
	var column := VBoxContainer.new()
	column.add_child(_label("Crafting", HEADING))
	# By hand first, then by name.
	var ids: Array = Content.recipes.keys()
	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var by_hand_a: bool = Content.recipes[a].station == &""
			var by_hand_b: bool = Content.recipes[b].station == &""
			return by_hand_a and not by_hand_b or (by_hand_a == by_hand_b and str(a) < str(b))
	)
	for id: StringName in ids:
		var recipe: RecipeDef = Content.recipes[id]
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.mouse_entered.connect(_show_info.bind(recipe.result))
		column.add_child(row)
		var icon := SlotView.new()
		icon.show_item(recipe.result, recipe.count)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.custom_minimum_size.x = 140
		row.add_child(text)
		text.add_child(_label(Content.item(recipe.result).display_name))
		var needs := HBoxContainer.new()
		text.add_child(needs)
		var inputs := {}
		for item: StringName in recipe.inputs:
			inputs[item] = _label("")
			needs.add_child(inputs[item])
		var status := _label("", BAD)
		text.add_child(status)
		var button := Button.new()
		button.text = "Craft"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void: craft_requested.emit(id))
		row.add_child(button)
		_recipes[id] = {inputs = inputs, status = status, button = button}
	return column


func toggle() -> void:
	visible = not visible
	_show_info(&"")


## data: Inventory.to_data, from the server.
func show_inventory(data: Dictionary) -> void:
	_inventory.load_data(data)
	for i in _slots.size():
		var slot := _inventory.slots[i]
		_slots[i].show_item(slot.get("item", &""), slot.get("count", 0))
	for kind: int in _worn:
		_worn[kind].show_item(_inventory.equipment[kind], 1)
	var weapon := Content.attack(_inventory.weapon(), false)
	var heavy := Content.attack(_inventory.weapon(), true)
	_stats.text = (
		"Light hit %d\nHeavy hit %d\nArmor %d  Health %d"
		% [
			weapon.damage,
			heavy.damage,
			_inventory.worn("armor"),
			Content.tuning.max_health + _inventory.worn("health"),
		]
	)
	_statuses.clear()
	_refresh()


func _process(_delta: float) -> void:
	if visible:
		_refresh()


## Each recipe's inputs as have/need, green or red, and why it can't be crafted, redrawn only
## when that changes.
func _refresh() -> void:
	for id: StringName in _recipes:
		var recipe: RecipeDef = Content.recipes[id]
		var status := Crafting.status(_inventory, recipe, player_at)
		if _statuses.get(id) == status:
			continue
		_statuses[id] = status
		var row: Dictionary = _recipes[id]
		for item: StringName in recipe.inputs:
			var have := _inventory.count_of(item)
			var need: int = recipe.inputs[item]
			var label: Label = row.inputs[item]
			label.text = "%s %d/%d" % [Content.item(item).display_name, have, need]
			label.add_theme_color_override("font_color", OK if have >= need else BAD)
		if status == Crafting.Status.AWAY_FROM_STATION:
			row.status.text = "Go to the %s" % _station_place(recipe.station)
		else:
			row.status.text = STATUS_TEXT[status]
		row.status.visible = row.status.text != ""
		row.button.disabled = status != Crafting.Status.READY


## "workbench at the spawn" for a station near the respawn point, else just its name.
# ponytail: one fixed workbench until M8 lets players build their own.
static func _station_place(station: StringName) -> String:
	var name := str(station).capitalize().to_lower()
	var at: Vector2 = Content.tuning.stations.get(station, Vector2.INF)
	if at.distance_to(Content.tuning.respawn_at) <= Content.tuning.station_reach * 3:
		return name + " at the spawn"
	return name


## Whether data dragged from one slot may drop on another: backpack to backpack, gear to its
## own equipment slot, and worn gear back into the backpack.
func can_drop(data: Dictionary, onto: SlotView) -> bool:
	if data.from == onto.index and data.worn == onto.worn:
		return false
	var item := _dragged(data)
	if onto.worn != -1:
		return data.worn == -1 and Content.item(item).slot == onto.worn
	return true


func drop(data: Dictionary, onto: SlotView) -> void:
	if onto.worn != -1:
		equip_requested.emit(data.from)
	elif data.worn == -1:
		move_requested.emit(data.from, onto.index)
	elif Content.item(onto.item) and Content.item(onto.item).slot == data.worn:
		# Gear of the same kind lies there: wearing it swaps the two.
		equip_requested.emit(onto.index)
	else:
		unequip_requested.emit(data.worn, onto.index)


func _dragged(data: Dictionary) -> StringName:
	if data.worn != -1:
		return _inventory.equipment[data.worn]
	return _inventory.slots[data.from].get("item", &"")


func _slot_view() -> SlotView:
	var view := SlotView.new()
	view.ui = self
	view.mouse_entered.connect(func() -> void: _show_info(view.item, view.worn != -1))
	view.gui_input.connect(_on_slot_input.bind(view))
	return view


## Right click wears what is in the backpack or takes off what is worn.
func _on_slot_input(event: InputEvent, view: SlotView) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	if view.worn != -1:
		unequip_requested.emit(view.worn, -1)
	elif Content.item(view.item) and Content.item(view.item).slot != ItemDef.Slot.NONE:
		equip_requested.emit(view.index)


## The info panel on an item, with what can be done with it; a hint while on none.
func _show_info(id: StringName, worn := false) -> void:
	var def := Content.item(id)
	if def == null:
		_info_title.text = "Info"
		_info_title.add_theme_color_override("font_color", HEADING)
		_info_body.text = (
			"Point at an item or recipe to see what it is.\n\n"
			+ "Fell trees and break rocks with E, beat enemies: what they drop comes to you "
			+ "when you walk near."
		)
		return
	_info_title.text = def.display_name
	_info_title.add_theme_color_override("font_color", ItemDef.RARITY_COLORS[def.rarity])
	var text := describe(id)
	if def.slot != ItemDef.Slot.NONE:
		text += "\n\n" + ("Right click to take off." if worn else "Right click to wear.")
	_info_body.text = text


func _label(text: String, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label
