class_name InventoryUi
extends CanvasLayer
## The inventory screen (Tab or I): the slot grid, the worn weapon and armor, and the recipes.
## Left click picks a slot up and puts it down on another (merge or swap); right click wears an
## item or takes it off. A recipe crafts on click once its inputs are there and, if it needs a
## station, the player stands at one. Every click is only a request: what the server's
## inventory looks like after it comes back through show_inventory.

signal move_requested(from: int, to: int)
signal equip_requested(index: int)
signal unequip_requested(kind: int)
signal craft_requested(recipe: StringName)

const SLOT := 20
const COLUMNS := 6
const FONT_SIZE := 8
const DIM := Color(1, 1, 1, 0.3)


## One slot: the item as a square in its color, outlined in its rarity's, with the count.
class SlotView:
	extends Control

	var item: StringName
	var count := 0
	var selected := false:
		set(value):
			selected = value
			queue_redraw()
	## Shown while empty, e.g. "W" for the weapon slot.
	var hint := ""

	func _init() -> void:
		custom_minimum_size = Vector2(InventoryUi.SLOT, InventoryUi.SLOT)

	func show_item(id: StringName, amount: int) -> void:
		item = id
		count = amount
		tooltip_text = InventoryUi.describe(id)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE if selected else InventoryUi.DIM, false, 1)
		var font := get_theme_default_font()
		var def := Content.item(item)
		if def == null:
			draw_string(font, Vector2(7, 13), hint, 0, -1, InventoryUi.FONT_SIZE, InventoryUi.DIM)
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


## Stations the player stands at, set by GameClient while the screen is open.
var stations := {}

var _inventory := Inventory.new(Content.tuning.inventory_size)
var _panel := PanelContainer.new()
var _slots: Array[SlotView] = []
var _worn := {}  # ItemDef.Slot -> SlotView
var _recipes := {}  # recipe id -> Button
## Slot picked up by a left click, -1 if none.
var _picked := -1


## Name, rarity and stats of an item, for tooltips.
static func describe(id: StringName) -> String:
	var def := Content.item(id)
	if def == null:
		return ""
	var lines := PackedStringArray(
		[def.display_name, ItemDef.Rarity.keys()[def.rarity].capitalize()]
	)
	if def.slot == ItemDef.Slot.WEAPON:
		lines.append("Light %d  Heavy %d" % [def.light.damage, def.heavy.damage])
	elif def.slot == ItemDef.Slot.ARMOR:
		lines.append("Armor %d  Health +%d" % [def.armor, def.health])
	return "\n".join(lines)


func _ready() -> void:
	visible = false
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	_panel.theme = theme
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	_panel.add_child(columns)

	var left := VBoxContainer.new()
	columns.add_child(left)
	var worn := HBoxContainer.new()
	left.add_child(worn)
	for kind: int in [ItemDef.Slot.WEAPON, ItemDef.Slot.ARMOR]:
		var view := SlotView.new()
		view.hint = "W" if kind == ItemDef.Slot.WEAPON else "A"
		view.gui_input.connect(_on_worn_input.bind(kind))
		worn.add_child(view)
		_worn[kind] = view
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	left.add_child(grid)
	for i in _inventory.slots.size():
		var view := SlotView.new()
		view.gui_input.connect(_on_slot_input.bind(i))
		grid.add_child(view)
		_slots.append(view)

	var right := VBoxContainer.new()
	columns.add_child(right)
	var title := Label.new()
	title.text = "Crafting"
	right.add_child(title)
	for id: StringName in Content.recipes:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: craft_requested.emit(id))
		right.add_child(button)
		_recipes[id] = button
	_refresh_recipes()


func toggle() -> void:
	visible = not visible
	_pick(-1)


## data: Inventory.to_data, from the server.
func show_inventory(data: Dictionary) -> void:
	_inventory.load_data(data)
	for i in _slots.size():
		var slot := _inventory.slots[i]
		_slots[i].show_item(slot.get("item", &""), slot.get("count", 0))
	for kind: int in _worn:
		_worn[kind].show_item(_inventory.equipment[kind], 1)
	_refresh_recipes()


func _process(_delta: float) -> void:
	if visible:
		_refresh_recipes()


## Each recipe's inputs, greyed out while it can't be crafted here.
func _refresh_recipes() -> void:
	for id: StringName in _recipes:
		var recipe: RecipeDef = Content.recipes[id]
		var parts := PackedStringArray()
		for item: StringName in recipe.inputs:
			parts.append("%d %s" % [recipe.inputs[item], Content.item(item).display_name])
		var text := "%s: %s" % [Content.item(recipe.result).display_name, ", ".join(parts)]
		if recipe.station != &"":
			text += " (%s)" % recipe.station
		var button: Button = _recipes[id]
		button.text = text
		button.tooltip_text = describe(recipe.result)
		var here := recipe.station == &"" or stations.has(recipe.station)
		button.disabled = not (here and _inventory.has_all(recipe.inputs))


func _on_slot_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		_pick(-1)
		equip_requested.emit(index)
	elif click.button_index == MOUSE_BUTTON_LEFT:
		if _picked == -1:
			if not _inventory.slots[index].is_empty():
				_pick(index)
		else:
			if _picked != index:
				move_requested.emit(_picked, index)
			_pick(-1)


func _on_worn_input(event: InputEvent, kind: int) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_pick(-1)
		unequip_requested.emit(kind)


func _pick(index: int) -> void:
	if _picked != -1:
		_slots[_picked].selected = false
	_picked = index
	if index != -1:
		_slots[index].selected = true
