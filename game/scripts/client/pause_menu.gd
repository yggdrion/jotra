class_name PauseMenu
extends CanvasLayer
## The escape menu: resume, settings, back to the start menu, quit. The game goes on behind
## it (other players are in it), but its dim layer takes the clicks.

signal menu_chosen
signal quit_chosen

var _settings := SettingsMenu.new()


func _ready() -> void:
	layer = 55
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 100
	box.add_theme_constant_override("separation", 4)
	center.add_child(box)
	for row: Array in [
		["Resume", hide],
		["Settings", _settings.open],
		["Quit to start menu", menu_chosen.emit],
		["Quit", quit_chosen.emit],
	]:
		var button := Button.new()
		button.text = row[0]
		button.add_theme_font_size_override("font_size", 8)
		button.pressed.connect(row[1])
		box.add_child(button)
	add_child(_settings)


## Escape: closes settings, else the menu, else opens it.
func escape() -> void:
	if _settings.visible:
		_settings.close()
	else:
		visible = not visible
