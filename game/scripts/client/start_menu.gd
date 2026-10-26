class_name StartMenu
extends CanvasLayer
## The first screen: play solo, host a game friends can join, or join one by its room code.
## Stays up with a status line while the game connects, and shows why when the player comes
## back from a game. Centered, so it fits any window (PLAN §6).

signal solo_chosen
signal host_chosen
signal join_chosen(code: String)

const CODE_LENGTH := 4

var _status := Label.new()
var _code := LineEdit.new()
var _buttons: Array[Button] = []


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
	box.add_child(_button("Play solo", solo_chosen.emit))
	box.add_child(_button("Host a game", host_chosen.emit))
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
	box.add_child(_button("Quit", get_tree().quit))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 8)
	_status.modulate = Color("c0cbdc")
	box.add_child(_status)


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
