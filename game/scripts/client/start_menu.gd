class_name StartMenu
extends CanvasLayer
## The first screen, in pages that each do one thing:
## - home: the character to play as, Play, Join a friend, Characters, Settings, Quit;
## - worlds: pick a solo world to play alone or host for friends, make one (name, seed) or
##   delete one after a confirmation;
## - join: the room code a friend's game shows;
## - characters: pick, make or delete a character (CharacterList);
## - create: a new character's name, look (a sheet and a tint) and starting kit (KitDef).
## A first start with no character opens on create. A status line under the pages says what is
## under way (it stays while the game connects) and why the player came back from a game.
## Centered, so it fits any window (PLAN §6).

signal solo_chosen(world: String)
signal host_chosen(world: String)
signal join_chosen(code: String)

const CODE_LENGTH := 4
const FONT_SIZE := 8
const HEADING := Color("feae34")
const DIM := Color("c0cbdc")
const WIDTH := 260

## The character to play as: {name, look, kit}, {} until one exists.
var character := {}

var _status := Label.new()
var _code := LineEdit.new()
var _buttons: Array[Button] = []
var _pages := {}
var _worlds := ItemList.new()
var _new_name := LineEdit.new()
var _new_seed := LineEdit.new()
var _confirm := Control.new()
var _confirm_text := Label.new()
var _confirm_yes := Callable()
var _settings := SettingsMenu.new()
var _home_preview: TextureRect
var _home_name := Label.new()
var _character_rows := VBoxContainer.new()
var _create_name := LineEdit.new()
var _create_look := 0
var _create_kit := &""
var _create_preview: TextureRect
var _kit_buttons := {}
var _kit_info := Label.new()
var _create_back: Button


func _ready() -> void:
	layer = 50
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	var backdrop := ColorRect.new()
	backdrop.color = Color("181425")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = theme
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = WIDTH
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	var title := Label.new()
	title.text = "Jotra"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	for page: Array in [
		["home", _home_page()],
		["worlds", _worlds_page()],
		["join", _join_page()],
		["characters", _characters_page()],
		["create", _create_page()],
	]:
		_pages[page[0]] = page[1]
		box.add_child(page[1])
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = DIM
	box.add_child(_status)
	add_child(_settings)
	_build_confirm()
	_confirm.theme = theme
	add_child(_confirm)
	_pick(CharacterList.last())
	_refresh_worlds()
	_show("home" if not character.is_empty() else "create")


## A line under the pages; busy greys the buttons out while something is under way.
func show_status(text: String, busy := false) -> void:
	_status.text = text
	for button in _buttons:
		button.disabled = busy
	_code.editable = not busy


## A character's first walk frame (facing down) in its tint, size px square.
static func preview(look: int, size: int) -> TextureRect:
	var rect := TextureRect.new()
	_set_preview(rect, look)
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect


static func _set_preview(rect: TextureRect, look: int) -> void:
	var frame := AtlasTexture.new()
	frame.atlas = PlayerView.SHEETS[PlayerView.sheet_of(look)]
	var size := PlayerView.frame_of(frame.atlas)
	frame.region = Rect2(0, 0, size, size)
	rect.texture = frame
	rect.modulate = PlayerView.TINTS[PlayerView.tint_of(look)]


func _show(page: String) -> void:
	for key: String in _pages:
		_pages[key].visible = key == page
	if page == "characters":
		_refresh_characters()
	if page == "create":
		_create_back.visible = not CharacterList.list().is_empty()
		_create_name.text = ""
		_create_look = randi() % Net.LOOKS
		_choose_kit(Content.kit_ids[0])
		_set_preview(_create_preview, _create_look)
	if page != "home" or _status.text.begins_with("Created"):
		_status.text = ""


func _pick(picked: Dictionary) -> void:
	character = picked
	if character.is_empty():
		return
	CharacterList.remember(character.name)
	_set_preview(_home_preview, character.look)
	var kit: KitDef = Content.kits.get(character.kit)
	_home_name.text = "%s\n%s" % [character.name, kit.display_name if kit else "No kit"]


# Home


func _home_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 4)
	var who := HBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 8)
	_home_preview = preview(0, 48)
	who.add_child(_home_preview)
	who.add_child(_home_name)
	page.add_child(who)
	page.add_child(_button("Play", _show.bind("worlds")))
	page.add_child(_button("Join a friend", _show.bind("join")))
	page.add_child(_button("Characters", _show.bind("characters")))
	page.add_child(_button("Settings", _settings.open))
	page.add_child(_button("Quit", get_tree().quit))
	return page


# Worlds


func _worlds_page() -> Control:
	var page := VBoxContainer.new()
	page.add_child(_label("Your worlds", HEADING))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	page.add_child(row)
	_worlds.custom_minimum_size = Vector2(150, 110)
	_worlds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worlds.item_activated.connect(func(_i: int) -> void: _play(solo_chosen))
	row.add_child(_worlds)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 100
	actions.add_child(_button("Play solo", _play.bind(solo_chosen)))
	actions.add_child(_button("Host for friends", _play.bind(host_chosen)))
	var hint := _label("Friends join with the code your game shows", DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(hint)
	actions.add_child(_button("Delete world", _ask_delete_world))
	row.add_child(actions)
	page.add_child(_label("New world", HEADING))
	var create_row := HBoxContainer.new()
	for field: LineEdit in [_new_name, _new_seed]:
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		create_row.add_child(field)
	_new_name.placeholder_text = "Name"
	_new_name.max_length = 24
	_new_seed.placeholder_text = "Seed (empty: random)"
	_new_name.text_submitted.connect(func(_text: String) -> void: _create_world())
	create_row.add_child(_button("Create", _create_world))
	page.add_child(create_row)
	page.add_child(_button("Back", _show.bind("home")))
	return page


func _play(chosen: Signal) -> void:
	var world := _selected_world()
	if world == "":
		show_status("Pick a world, or make one below")
		return
	chosen.emit(world)


## Fills the list; a first start with no world gets one with a random seed.
func _refresh_worlds(select := "") -> void:
	var worlds := WorldList.list()
	if worlds.is_empty():
		WorldList.create("World", randi())
		worlds = WorldList.list()
	_worlds.clear()
	for world in worlds:
		var index := _worlds.add_item("%s  (seed %d)" % [world.name, world.seed])
		_worlds.set_item_metadata(index, world.name)
		if world.name == select or index == 0:
			_worlds.select(index)


func _selected_world() -> String:
	var picked := _worlds.get_selected_items()
	return _worlds.get_item_metadata(picked[0]) if not picked.is_empty() else ""


## A name, and a seed that is a number or any text (empty: random).
func _create_world() -> void:
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
	_refresh_worlds(name_text)


func _ask_delete_world() -> void:
	var world := _selected_world()
	if world == "":
		return
	_ask(
		"Delete %s and everything built in it?" % world,
		func() -> void:
			WorldList.delete(world)
			_refresh_worlds()
	)


# Join


func _join_page() -> Control:
	var page := VBoxContainer.new()
	page.add_child(_label("Join a friend", HEADING))
	var hint := _label("Enter the %d-letter code their game shows" % CODE_LENGTH, DIM)
	page.add_child(hint)
	var row := HBoxContainer.new()
	_code.placeholder_text = "Code"
	_code.max_length = CODE_LENGTH
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.text_changed.connect(
		func(text: String) -> void:
			var caret := _code.caret_column
			_code.text = text.to_upper()
			_code.caret_column = caret
	)
	_code.text_submitted.connect(func(_text: String) -> void: _join())
	row.add_child(_code)
	row.add_child(_button("Join", _join))
	page.add_child(row)
	page.add_child(_button("Back", _show.bind("home")))
	return page


func _join() -> void:
	var code := _code.text.strip_edges()
	if code.length() != CODE_LENGTH:
		show_status("Enter the %d-letter code of the game to join" % CODE_LENGTH)
		return
	join_chosen.emit(code)


# Characters


func _characters_page() -> Control:
	var page := VBoxContainer.new()
	page.add_child(_label("Characters", HEADING))
	page.add_child(_label("Each world keeps its own progress for a character", DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 150
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_character_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_character_rows)
	page.add_child(scroll)
	page.add_child(_button("New character", _show.bind("create")))
	page.add_child(_button("Back", _show.bind("home")))
	return page


func _refresh_characters() -> void:
	for child in _character_rows.get_children():
		child.queue_free()
	for c in CharacterList.list():
		var row := HBoxContainer.new()
		row.add_child(preview(c.look, 24))
		var kit: KitDef = Content.kits.get(c.kit)
		var pick := Button.new()
		pick.text = "%s  (%s)" % [c.name, kit.display_name if kit else "no kit"]
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.toggle_mode = true
		pick.button_pressed = not character.is_empty() and c.name == character.name
		pick.pressed.connect(
			func() -> void:
				_pick(c)
				_show("home")
		)
		row.add_child(pick)
		var delete := Button.new()
		delete.text = "Delete"
		delete.pressed.connect(_ask_delete_character.bind(c.name))
		row.add_child(delete)
		_character_rows.add_child(row)


func _ask_delete_character(character_name: String) -> void:
	_ask(
		"Forget %s? Worlds keep what they saved of it." % character_name,
		func() -> void:
			CharacterList.delete(character_name)
			if not character.is_empty() and character.name == character_name:
				_pick(CharacterList.last())
			if character.is_empty():
				_show("create")
			else:
				_refresh_characters()
	)


# Create


func _create_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 4)
	page.add_child(_label("New character", HEADING))
	_create_name.placeholder_text = "Name"
	_create_name.max_length = 32
	page.add_child(_create_name)
	var look_row := HBoxContainer.new()
	look_row.add_theme_constant_override("separation", 6)
	_create_preview = preview(0, 48)
	look_row.add_child(_create_preview)
	var look_controls := VBoxContainer.new()
	var body := HBoxContainer.new()
	body.add_child(_label("Body"))
	body.add_child(_small_button("<", _step_look.bind(-PlayerView.TINTS.size())))
	body.add_child(_small_button(">", _step_look.bind(PlayerView.TINTS.size())))
	look_controls.add_child(body)
	var colors := HBoxContainer.new()
	colors.add_child(_label("Color"))
	for i in PlayerView.TINTS.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		var style := StyleBoxFlat.new()
		style.bg_color = PlayerView.TINTS[i]
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", style)
		swatch.pressed.connect(_set_tint.bind(i))
		colors.add_child(swatch)
	look_controls.add_child(colors)
	look_row.add_child(look_controls)
	page.add_child(look_row)
	page.add_child(_label("Starting kit"))
	var kits := HBoxContainer.new()
	for id in Content.kit_ids:
		var button := Button.new()
		button.text = Content.kits[id].display_name
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_choose_kit.bind(id))
		_kit_buttons[id] = button
		kits.add_child(button)
	page.add_child(kits)
	_kit_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kit_info.custom_minimum_size.x = WIDTH
	_kit_info.modulate = DIM
	page.add_child(_kit_info)
	page.add_child(_button("Create", _create_character))
	_create_back = _button("Back", _show.bind("characters"))
	page.add_child(_create_back)
	return page


func _step_look(by: int) -> void:
	_create_look = posmod(_create_look + by, Net.LOOKS)
	_set_preview(_create_preview, _create_look)


func _set_tint(tint: int) -> void:
	_create_look = PlayerView.sheet_of(_create_look) * PlayerView.TINTS.size() + tint
	_set_preview(_create_preview, _create_look)


func _choose_kit(id: StringName) -> void:
	_create_kit = id
	for kit: StringName in _kit_buttons:
		_kit_buttons[kit].button_pressed = kit == id
	_kit_info.text = Content.kits[id].description


func _create_character() -> void:
	var name_text := _create_name.text.strip_edges()
	var problem := CharacterList.create(name_text, _create_look, _create_kit)
	if problem != "":
		show_status(problem)
		return
	_pick(CharacterList.last())
	_show("home")
	show_status("Created %s" % name_text)


# Shared


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	_buttons.append(button)
	return button


func _small_button(text: String, pressed: Callable) -> Button:
	var button := _button(text, pressed)
	button.custom_minimum_size.x = 16
	return button


func _label(text: String, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	return label


## A yes/no question over the menu; yes runs on_yes.
func _ask(text: String, on_yes: Callable) -> void:
	_confirm_text.text = text
	_confirm_yes = on_yes
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
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size.x = 200
	box.add_child(_confirm_text)
	var row := HBoxContainer.new()
	box.add_child(row)
	for entry: Array in [["Yes", true], ["Cancel", false]]:
		var button := Button.new()
		button.text = entry[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_answer.bind(entry[1]))
		row.add_child(button)


func _answer(yes: bool) -> void:
	_confirm.visible = false
	if yes and _confirm_yes.is_valid():
		_confirm_yes.call()
