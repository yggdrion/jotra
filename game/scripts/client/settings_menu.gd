class_name SettingsMenu
extends CanvasLayer
## Two tabs: General (volume, screenshake, fullscreen, the HUD's key panel) and Controls
## (Settings.ACTIONS: click one, press its new key), the controls scrolling so the menu fits the
## 360 px high view. Saved as they change. Used by the start menu and the escape menu; close()
## ends it and emits closed.

signal closed

## Height of a tab's page; with the title, note and Back it stays inside the 360 px view.
const PAGE_HEIGHT := 220

var _rebinding := &""
var _buttons := {}  # action -> Button
var _note := Label.new()
var _tabs := TabContainer.new()


func _ready() -> void:
	layer = 60
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 180
	box.add_theme_constant_override("separation", 3)
	center.add_child(box)
	box.add_child(_label("Settings", 12))
	_tabs.add_theme_font_size_override("font_size", 8)
	_tabs.custom_minimum_size.y = PAGE_HEIGHT
	box.add_child(_tabs)
	_tabs.add_child(_general())
	_tabs.add_child(_controls())
	_note.add_theme_font_size_override("font_size", 8)
	_note.modulate = Color("c0cbdc")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_note)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 8)
	back.pressed.connect(close)
	box.add_child(back)
	_tabs.tab_changed.connect(func(_tab: int) -> void: _show_note())
	_show_keys()


func _general() -> Control:
	var box := VBoxContainer.new()
	box.name = "General"
	box.add_theme_constant_override("separation", 3)
	box.add_child(_row("Volume", _slider(Settings.volume, _set_volume)))
	box.add_child(_row("Screenshake", _slider(Settings.shake, _set_shake)))
	var fullscreen := CheckBox.new()
	fullscreen.button_pressed = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	fullscreen.toggled.connect(
		func(on: bool) -> void:
			Settings.set_fullscreen(on)
			Settings.save_file()
	)
	box.add_child(_row("Fullscreen (F11)", fullscreen))
	var key_panel := CheckBox.new()
	key_panel.button_pressed = Settings.key_panel
	key_panel.toggled.connect(
		func(on: bool) -> void:
			Settings.key_panel = on
			Settings.apply()
			Settings.save_file()
	)
	box.add_child(_row("Key panel", key_panel))
	return box


func _controls() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)
	for action: StringName in Settings.ACTIONS:
		var button := Button.new()
		button.custom_minimum_size.x = 60
		button.add_theme_font_size_override("font_size", 8)
		button.pressed.connect(_start_rebind.bind(action))
		_buttons[action] = button
		box.add_child(_row(Settings.ACTIONS[action][0], button))
	return scroll


func _set_volume(value: float) -> void:
	Settings.volume = value
	Settings.apply()


func _set_shake(value: float) -> void:
	Settings.shake = value


## A 0-1 slider in steps of 5%, calling changed and saving on every move.
func _slider(value: float, changed: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.x = 80
	slider.value_changed.connect(
		func(to: float) -> void:
			changed.call(to)
			Settings.save_file()
	)
	return slider


func open() -> void:
	_rebinding = &""
	_show_note()
	_show_keys()
	visible = true


func close() -> void:
	_rebinding = &""
	visible = false
	closed.emit()


## Waits for the key of the action being rebound, before anything else sees it.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _rebinding == &"" or key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var code := int(key.physical_keycode)
	if code != KEY_ESCAPE:
		var other := Settings.clash(_rebinding, code)
		if other != &"":
			var taken := OS.get_keycode_string(key.physical_keycode)
			_note.text = "%s is already %s" % [taken, Settings.ACTIONS[other][0]]
			return
		Settings.keys[_rebinding] = code
		Settings.apply()
		Settings.save_file()
		_note.text = ""
	_rebinding = &""
	_show_keys()


func _show_note() -> void:
	var controls := _tabs.current_tab == 1
	_note.text = "Click a control, then press its new key (Esc cancels)" if controls else ""


func _start_rebind(action: StringName) -> void:
	_rebinding = action
	_show_keys()


func _show_keys() -> void:
	for action: StringName in _buttons:
		var names := PackedStringArray()
		for key: int in Settings.keys_of(action):
			names.append(OS.get_keycode_string(key as Key))
		_buttons[action].text = "press a key..." if action == _rebinding else " / ".join(names)


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(text, 8)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	return row


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label
