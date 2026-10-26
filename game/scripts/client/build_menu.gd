class_name BuildMenu
extends CanvasLayer
## The piece picker shown in build mode: every piece under its category heading with what it costs
## against what the player has, an info line on the one the mouse is over, and a hotbar of the
## recent pieces (1-6). A click only says picked; BuildMode owns the choice.

signal picked(id: StringName)

const HOTBAR := 6
const FONT_SIZE := 8
const HEADING := Color("feae34")
const OK := Color("63c74d")
const BAD := Color("e43b44")
const BOTTOM := 48

## The hotbar, newest first.
var recent: Array[StringName] = []
var selected: StringName
var _info := Label.new()
var _hotbar := HBoxContainer.new()
## {piece id: {item id: Label}} of the cost labels.
var _costs := {}


## Puts id at the front of a hotbar unless it is on it already (so digits don't shuffle), the
## oldest falling off the end.
static func remember(bar: Array[StringName], id: StringName, size: int) -> Array[StringName]:
	if id in bar:
		return bar
	var out: Array[StringName] = [id]
	out.append_array(bar)
	return out.slice(0, size)


## What a piece is and does, for the info line.
static func describe(def: PieceDef) -> String:
	var facts := PackedStringArray()
	if def.door:
		facts.append("E opens and closes it")
	elif def.blocks:
		facts.append("blocks players and enemies")
	if def.station:
		facts.append("craft next to it")
	if def.storage > 0:
		facts.append("E opens its %d slots" % def.storage)
	if def.light > 0:
		facts.append("lights the night")
	if def.flat:
		facts.append("walked on")
	facts.append("%d health" % def.health)
	return "%s: %s" % [def.display_name, ", ".join(facts)]


func _ready() -> void:
	visible = false
	recent.assign(Content.piece_ids.slice(0, HOTBAR))
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	theme.set_constant("icon_max_width", "Button", 16)
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -BOTTOM
	add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	rows.add_child(_hotbar)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	rows.add_child(columns)
	var by_category := {}
	for id in Content.piece_ids:
		var category: String = Content.piece(id).category
		if not by_category.has(category):
			by_category[category] = VBoxContainer.new()
			columns.add_child(by_category[category])
			by_category[category].add_child(_label(category, HEADING))
		by_category[category].add_child(_row(id))
	_info.custom_minimum_size.x = 260
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	rows.add_child(_info)
	_show_recent()


## Marks a piece as the chosen one and moves it onto the hotbar.
func choose(id: StringName) -> void:
	selected = id
	recent = remember(recent, id, HOTBAR)
	_show_recent()


## The piece on a hotbar slot (0-5), &"" if it is empty.
func hotbar_piece(slot: int) -> StringName:
	return recent[slot] if slot >= 0 and slot < recent.size() else &""


## Each piece's cost as have/need, green or red.
func refresh(inventory: Inventory) -> void:
	for id: StringName in _costs:
		var cost: Dictionary = Content.piece(id).cost
		for item: StringName in cost:
			var have := inventory.count_of(item)
			var label: Label = _costs[id][item]
			label.text = "%s %d/%d" % [Content.item(item).display_name, have, cost[item]]
			label.add_theme_color_override("font_color", OK if have >= cost[item] else BAD)


func _row(id: StringName) -> Control:
	var def := Content.piece(id)
	var row := HBoxContainer.new()
	var button := Button.new()
	button.text = def.display_name
	button.icon = def.icon
	button.custom_minimum_size.x = 80
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func() -> void: picked.emit(id))
	button.mouse_entered.connect(func() -> void: _info.text = describe(def))
	row.add_child(button)
	_costs[id] = {}
	for item: StringName in def.cost:
		_costs[id][item] = _label("")
		row.add_child(_costs[id][item])
	return row


func _show_recent() -> void:
	for child in _hotbar.get_children():
		child.queue_free()
	for i in recent.size():
		var id := recent[i]
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = id == selected
		button.text = str(i + 1)
		button.icon = Content.piece(id).icon
		button.pressed.connect(func() -> void: picked.emit(id))
		_hotbar.add_child(button)


func _label(text: String, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label
