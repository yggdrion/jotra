class_name StartMenu
extends CanvasLayer
## The first screen, in pages that each do one thing:
## - characters: who plays, as cards (CharacterList) to pick, make or delete one, then
##   Continue (or a double click); Settings and Quit;
## - worlds: where to, for the picked character: a solo world to play alone (Solo) or open
##   to friends (Host), make one (name, seed) or delete one after a confirmation, or join a
##   friend's game by the room code it shows;
## - create: a new character's name, look (a sheet and a tint) and starting kit (KitDef).
## A first start with no character opens on create. A status line under the pages says what is
## under way (it stays while the game connects) and why the player came back from a game.
## Centered, so it fits any window (PLAN §6).

signal solo_chosen(world: String)
signal host_chosen(world: String)
signal join_chosen(code: String)

const CODE_LENGTH := 8
const FONT_SIZE := 8
const HEADING := Color("feae34")
const DIM := Color("c0cbdc")
const WIDTH := 260
## A character card on the first page, four to a row.
const CARD := Vector2(61, 76)

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
var _character_cards := GridContainer.new()
var _card_scroll: ScrollContainer
var _continue: Button
var _worlds_back: Button
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
		["characters", _characters_page()],
		["worlds", _worlds_page()],
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
	_show("characters" if not character.is_empty() else "create")


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
	if page == "worlds":
		_worlds_back.text = "< %s" % character.name
	if page == "create":
		_create_back.visible = not CharacterList.list().is_empty()
		_create_name.text = ""
		_create_look = randi() % Net.LOOKS
		_choose_kit(Content.kit_ids[0])
		_set_preview(_create_preview, _create_look)
	if page != "characters" or _status.text.begins_with("Created"):
		_status.text = ""


func _pick(picked: Dictionary) -> void:
	character = picked
	if character.is_empty():
		return
	CharacterList.remember(character.name)
	if _continue:
		_continue.text = "Continue as %s" % character.name


# Worlds


func _worlds_page() -> Control:
	var page := VBoxContainer.new()
	_worlds_back = _button("<", _show.bind("characters"))
	_worlds_back.flat = true
	_worlds_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(_worlds_back)
	page.add_child(_label("Your worlds", HEADING))
	_worlds.custom_minimum_size = Vector2(0, 90)
	_worlds.item_activated.connect(func(_i: int) -> void: _play(solo_chosen))
	page.add_child(_worlds)
	var actions := HBoxContainer.new()
	var solo := _button("Solo", _play.bind(solo_chosen))
	solo.add_theme_color_override("font_color", HEADING)
	for button: Button in [solo, _button("Host", _play.bind(host_chosen))]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	actions.add_child(_button("Delete", _ask_delete_world))
	page.add_child(actions)
	page.add_child(_label("Host: friends join with the code your game shows", DIM))
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
	page.add_child(_label("Friend's world", HEADING))
	page.add_child(_label("Enter the %d-letter code their game shows" % CODE_LENGTH, DIM))
	var join_row := HBoxContainer.new()
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
	join_row.add_child(_code)
	join_row.add_child(_button("Join", _join))
	page.add_child(join_row)
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


func _join() -> void:
	var code := _code.text.strip_edges()
	if code.length() != CODE_LENGTH:
		show_status("Enter the %d-letter code of the game to join" % CODE_LENGTH)
		return
	join_chosen.emit(code)


# Characters


func _characters_page() -> Control:
	var page := VBoxContainer.new()
	page.add_child(_label("Who plays", HEADING))
	var scroll := ScrollContainer.new()
	_card_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_character_cards.columns = 4
	_character_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_cards.add_theme_constant_override("h_separation", 4)
	_character_cards.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_character_cards)
	page.add_child(scroll)
	var hint_row := HBoxContainer.new()
	var hint := _label("Each world keeps its own progress for a character", DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_row.add_child(hint)
	hint_row.add_child(_button("Delete", func() -> void: _ask_delete_character(character.name)))
	page.add_child(hint_row)
	_continue = _button("Continue", _show.bind("worlds"))
	_continue.add_theme_color_override("font_color", HEADING)
	page.add_child(_continue)
	var row := HBoxContainer.new()
	for button: Button in [_button("Settings", _settings.open), _button("Quit", get_tree().quit)]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	page.add_child(row)
	return page


## A card per character (a click picks it, a double click goes on with it) and one to make a
## new one.
func _refresh_characters() -> void:
	for child in _character_cards.get_children():
		child.queue_free()
	var group := ButtonGroup.new()
	for c in CharacterList.list():
		var card := _card()
		card.toggle_mode = true
		card.button_group = group
		var picked := StyleBoxFlat.new()
		picked.bg_color = Color(HEADING, 0.15)
		picked.border_color = HEADING
		picked.set_border_width_all(1)
		picked.set_corner_radius_all(2)
		card.add_theme_stylebox_override("pressed", picked)
		card.add_theme_stylebox_override("hover_pressed", picked)
		card.button_pressed = not character.is_empty() and c.name == character.name
		card.pressed.connect(_pick.bind(c))
		card.gui_input.connect(
			func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.double_click:
					_pick(c)
					_show("worlds")
		)
		var kit: KitDef = Content.kits.get(c.kit)
		var box := card.get_child(0)
		var look := preview(c.look, 44)
		look.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(look)
		box.add_child(_card_label(c.name, Color.WHITE))
		box.add_child(_card_label(kit.display_name if kit else "No kit", DIM))
		_character_cards.add_child(card)
	var new := _card()
	new.pressed.connect(_show.bind("create"))
	new.get_child(0).add_child(_card_label("+\nNew", DIM))
	_character_cards.add_child(new)
	# One row of cards per four, up to two shown; more scroll.
	var rows := mini(ceili((CharacterList.list().size() + 1) / 4.0), 2)
	_card_scroll.custom_minimum_size.y = rows * (CARD.y + 4)


## A button the size of a character card with a centered column to fill.
func _card() -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	return card


func _card_label(text: String, color: Color) -> Label:
	var label := _label(text, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = CARD.x - 4
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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
	_show("characters")
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
