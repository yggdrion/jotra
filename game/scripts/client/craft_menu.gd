class_name CraftMenu
extends CanvasLayer
## The recipe list E opens at a workbench: every recipe under its category heading with what it
## needs against what the player has and, if it can't be crafted, why, a search box, and craft x1
## and x5 buttons. Only a request: craft_requested goes to the server once per craft.

signal craft_requested(recipe: StringName)

const FONT_SIZE := 8
const HEADING := Color("feae34")
const OK := Color("63c74d")
const BAD := Color("e43b44")
const TIMES := 5

## Set by the client each frame: its copy of the inventory and Building.stations_near.
var inventory: Inventory
var stations := {}
var _search := LineEdit.new()
## {recipe id: {row, inputs {item: Label}, status, once, many}}
var _recipes := {}
## {category: its heading Label}
var _headings := {}
var _close_hint: Label
var _statuses := {}


## Whether a recipe shows for a search: its result's name or a category contains the text.
static func matches(recipe: RecipeDef, query: String) -> bool:
	var text := query.strip_edges().to_lower()
	return (
		text == ""
		or Content.item(recipe.result).display_name.to_lower().contains(text)
		or recipe.category.to_lower().contains(text)
	)


func _ready() -> void:
	visible = false
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	rows.add_child(_label("Craft", HEADING))
	_search.placeholder_text = "Search"
	_search.text_changed.connect(func(_text: String) -> void: _filter())
	rows.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 150)
	rows.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var ids: Array = Content.recipes.keys()
	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var ca: String = Content.recipes[a].category
			var cb: String = Content.recipes[b].category
			return ca < cb or (ca == cb and str(a) < str(b))
	)
	for id: StringName in ids:
		var recipe: RecipeDef = Content.recipes[id]
		if not _headings.has(recipe.category):
			_headings[recipe.category] = _label(recipe.category, HEADING)
			list.add_child(_headings[recipe.category])
		list.add_child(_row(id, recipe))
	_close_hint = _label("", Color(1, 1, 1, 0.35))
	rows.add_child(_close_hint)


func toggle() -> void:
	visible = not visible
	if visible:
		_close_hint.text = "%s or Esc: close" % KeyHint.key(&"interact")
		_search.clear()
		_filter()


## Whether the search box is taking typed keys, so the player doesn't walk on w, a, s and d.
func typing() -> bool:
	return visible and _search.has_focus()


func _process(_delta: float) -> void:
	if visible and inventory:
		_refresh()


func _row(id: StringName, recipe: RecipeDef) -> Control:
	var row := HBoxContainer.new()
	var icon := InventoryUi.SlotView.new()
	icon.show_item(recipe.result, recipe.count)
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var once := _button("x1", 1, id)
	var many := _button("x%d" % TIMES, TIMES, id)
	row.add_child(once)
	row.add_child(many)
	_recipes[id] = {row = row, inputs = inputs, status = status, once = once, many = many}
	return row


## ponytail: x5 sends five requests and the server refuses the ones it can't pay, instead of the
## client working out how many fit; add a count to Net.craft if that ever shows.
func _button(text: String, times: int, id: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(
		func() -> void:
			for i in times:
				craft_requested.emit(id)
	)
	return button


func _filter() -> void:
	var shown := {}
	for id: StringName in _recipes:
		var recipe: RecipeDef = Content.recipes[id]
		var found := matches(recipe, _search.text)
		_recipes[id].row.visible = found
		shown[recipe.category] = shown.get(recipe.category, false) or found
	for category: String in _headings:
		_headings[category].visible = shown.get(category, false)


## Each recipe's inputs as have/need, green or red, and why it can't be crafted, redrawn only
## when the status changes.
func _refresh() -> void:
	for id: StringName in _recipes:
		var recipe: RecipeDef = Content.recipes[id]
		var status := Crafting.status(inventory, recipe, stations)
		var row: Dictionary = _recipes[id]
		for item: StringName in recipe.inputs:
			var have := inventory.count_of(item)
			var label: Label = row.inputs[item]
			label.text = "%s %d/%d" % [Content.item(item).display_name, have, recipe.inputs[item]]
			label.add_theme_color_override("font_color", OK if have >= recipe.inputs[item] else BAD)
		if _statuses.get(id) == status:
			continue
		_statuses[id] = status
		row.status.text = InventoryUi.STATUS_TEXT.get(status, "Needs a %s nearby" % recipe.station)
		row.status.visible = row.status.text != ""
		row.once.disabled = status != Crafting.Status.READY
		row.many.disabled = status != Crafting.Status.READY


func _label(text: String, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label
