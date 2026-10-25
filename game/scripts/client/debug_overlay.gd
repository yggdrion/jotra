class_name DebugOverlay
extends CanvasLayer
## F3 toggles a corner readout of fps and the connection (GameClient.debug_lines). Off by
## default; release builds have it too, for playtests.

## How often the text refreshes, in seconds.
const REFRESH := 0.25
const FONT_SIZE := 8

var client: GameClient
var _label := Label.new()
var _wait := 0.0


func _ready() -> void:
	layer = 100
	visible = false
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.6)
	box.set_content_margin_all(3)
	var panel := PanelContainer.new()
	panel.position = Vector2(2, 2)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)
	add_child(panel)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		_wait = 0.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REFRESH
	var lines := PackedStringArray(["FPS %d" % Engine.get_frames_per_second()])
	lines.append_array(client.debug_lines())
	_label.text = "\n".join(lines)
