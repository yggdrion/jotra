class_name StartMenu
extends CanvasLayer
## The first screen: pick a solo world (create one with a name and seed, or delete one after
## a confirmation) to play solo or to host for friends, join a game by its room code, change
## the settings or quit.
## Stays up with a status line while the game connects, and shows why when the player comes
## back from a game. Centered, so it fits any window (PLAN §6).

signal solo_chosen(world: String)
signal host_chosen(world: String)
signal join_chosen(code: String)

const CODE_LENGTH := 4

var _status := Label.new()
var _code := LineEdit.new()
var _buttons: Array[Button] = []
var _worlds := OptionButton.new()
var _new_name := LineEdit.new()
var _new_seed := LineEdit.new()
var _confirm := Control.new()
var _confirm_text := Label.new()
var _settings := SettingsMenu.new()


func _ready() -> void:
	layer = 50
	var backdrop := ColorRect.new()
	backdrop.color = Color("181425")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 140
	box.add_theme_constant_override("separation", 4)
	center.add_child(box)
	var title := Label.new()
	title.text = "Jotra"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_worlds.add_theme_font_size_override("font_size", 8)
	_worlds.get_popup().add_theme_font_size_override("font_size", 8)
	box.add_child(_worlds)
	box.add_child(_button("Play solo", func() -> void: solo_chosen.emit(_selected())))
	box.add_child(_button("Host a game", func() -> void: host_chosen.emit(_selected())))
	box.add_child(_button("Delete world", _ask_delete))
	var create_row := HBoxContainer.new()
	for field: LineEdit in [_new_name, _new_seed]:
		field.custom_minimum_size.x = 40
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_font_size_override("font_size", 8)
		create_row.add_child(field)
	_new_name.placeholder_text = "Name"
	_new_name.max_length = 24
	_new_seed.placeholder_text = "Seed"
	box.add_child(create_row)
	box.add_child(_button("Create world", _create))
	var join_row := HBoxContainer.new()
	_code.placeholder_text = "Code"
	_code.max_length = CODE_LENGTH
	_code.custom_minimum_size.x = 40
	_code.add_theme_font_size_override("font_size", 8)
	_code.text_changed.connect(
		func(text: String) -> void:
			var caret := _code.caret_column
			_code.text = text.to_upper()
			_code.caret_column = caret
	)
	_code.text_submitted.connect(func(_text: String) -> void: _join())
	join_row.add_child(_code)
	var join := _button("Join", _join)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(join)
	box.add_child(join_row)
	box.add_child(_button("Settings", _settings.open))
	box.add_child(_button("Quit", get_tree().quit))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 8)
	_status.modulate = Color("c0cbdc")
	box.add_child(_status)
	add_child(_settings)
	_build_confirm()
	_refresh()


## A line under the buttons; busy greys the buttons out while something is under way.
func show_status(text: String, busy := false) -> void:
	_status.text = text
	for button in _buttons:
		button.disabled = busy
	_code.editable = not busy


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 8)
	button.pressed.connect(pressed)
	_buttons.append(button)
	return button


func _join() -> void:
	var code := _code.text.strip_edges()
	if code.length() != CODE_LENGTH:
		show_status("Enter the %d-letter code of the game to join" % CODE_LENGTH)
		return
	join_chosen.emit(code)


## Fills the list; a first start with no world gets one with a random seed.
func _refresh(select := "") -> void:
	var worlds := WorldList.list()
	if worlds.is_empty():
		WorldList.create("World", randi())
		worlds = WorldList.list()
	_worlds.clear()
	for world in worlds:
		_worlds.add_item("%s  (seed %d)" % [world.name, world.seed])
		_worlds.set_item_metadata(-1, world.name)
		if world.name == select:
			_worlds.select(_worlds.item_count - 1)


func _selected() -> String:
	return _worlds.get_selected_metadata() if _worlds.selected >= 0 else ""


## A name, and a seed that is a number or any text (empty: random).
func _create() -> void:
	var seed_text := _new_seed.text.strip_edges()
	var world_seed := (
		randi()
		if seed_text == ""
		else (int(seed_text) if seed_text.is_valid_int() else seed_text.hash())
	)
	var name_text := _new_name.text.strip_edges()
	var problem := WorldList.create(name_text, world_seed)
	if problem == "":
		_new_name.text = ""
		_new_seed.text = ""
	show_status(problem if problem != "" else "Created %s" % name_text)
	_refresh(name_text)


func _ask_delete() -> void:
	_confirm_text.text = "Delete %s and everything built in it?" % _selected()
	_confirm.visible = true


func _build_confirm() -> void:
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)
	var box := VBoxContainer.new()
	center.add_child(box)
	_confirm_text.add_theme_font_size_override("font_size", 8)
	box.add_child(_confirm_text)
	var row := HBoxContainer.new()
	box.add_child(row)
	for entry: Array in [["Delete", true], ["Cancel", false]]:
		var button := Button.new()
		button.text = entry[0]
		button.add_theme_font_size_override("font_size", 8)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_answer.bind(entry[1]))
		row.add_child(button)
	add_child(_confirm)


func _answer(delete: bool) -> void:
	_confirm.visible = false
	if delete:
		WorldList.delete(_selected())
		_refresh()
