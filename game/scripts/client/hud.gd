class_name Hud
extends CanvasLayer
## Health and stamina bars in the bottom-left corner, and "You died" in the middle while dead.
## Anchored to the screen, as the visible area differs per player (PLAN §6).

const BAR := Vector2(80, 5)
const MARGIN := 6
const HEALTH_COLOR := Color("e43b44")
const STAMINA_COLOR := Color("feae34")

var _bars := Control.new()
var _died := Label.new()
var _health := 1.0
var _stamina := 1.0


func _ready() -> void:
	_bars.size = Vector2(BAR.x, BAR.y * 2 + 2)
	_bars.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, MARGIN
	)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	add_child(_bars)
	_died.text = "You died"
	_died.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_died.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_died.set_anchors_preset(Control.PRESET_FULL_RECT)
	_died.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_died.visible = false
	add_child(_died)


## Both 0..1.
func show_stats(health: float, stamina: float) -> void:
	_health = health
	_stamina = stamina
	_died.visible = health <= 0.0
	_bars.queue_redraw()


func _draw_bars() -> void:
	for row: Array in [[0, _health, HEALTH_COLOR], [BAR.y + 2, _stamina, STAMINA_COLOR]]:
		var at := Vector2(0, row[0])
		_bars.draw_rect(Rect2(at, BAR), Color(0, 0, 0, 0.6))
		_bars.draw_rect(Rect2(at, Vector2(BAR.x * row[1], BAR.y)), row[2])
