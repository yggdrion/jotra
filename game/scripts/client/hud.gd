class_name Hud
extends CanvasLayer
## Health, stamina and hunger bars in the bottom-left corner with the day above them, "You
## died" in the middle while dead, announcements like nightfall at the top, a prompt for what
## the player can do right here above the bottom edge, and the inventory key in the
## bottom-right corner, the room code friends join with in the top-right one when hosting,
## and the dungeon buffs held in the top-left one. The minimap sits above the key hint.
## Anchored to the screen, as the visible area differs per player
## (PLAN §6).

const BAR := Vector2(80, 5)
const MARGIN := 6
const HEALTH_COLOR := Color("e43b44")
const STAMINA_COLOR := Color("feae34")
const HUNGER_COLOR := Color("b86f50")
## Seconds an announcement stays, then fades.
const ANNOUNCE_TIME := 3.0

var _bars := Control.new()
var _died := Label.new()
var _prompt := Label.new()
var _keys := Label.new()
var _clock := Label.new()
var _announce := Label.new()
var _room := Label.new()
var _buffs := VBoxContainer.new()
var _health := 1.0
var _stamina := 1.0
var _hunger := 1.0
var _announce_tween: Tween


func _ready() -> void:
	_bars.size = Vector2(BAR.x, BAR.y * 3 + 4)
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
	for label: Label in [_prompt, _keys, _clock, _announce, _room]:
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = -40
	_prompt.offset_bottom = -28
	_keys.text = "[Tab] Inventory and crafting  [M] Map"
	_keys.modulate = Color(1, 1, 1, 0.6)
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keys.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN
	)
	_keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_clock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_clock.offset_left = MARGIN
	_clock.offset_bottom = -MARGIN - _bars.size.y - 1
	_clock.offset_top = _clock.offset_bottom - 12
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_announce.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_announce.offset_top = 24
	_announce.visible = false
	_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_room.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN
	)
	_room.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_buffs.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, MARGIN
	)
	_buffs.add_theme_constant_override("separation", 0)
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buffs)


## All 0..1.
func show_stats(health: float, stamina: float, hunger: float) -> void:
	_health = health
	_stamina = stamina
	_hunger = hunger
	_died.visible = health <= 0.0
	_bars.queue_redraw()


## What the player can do here, e.g. "[E] Fell tree"; "" hides it.
func show_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""


## The day and how long until it changes, e.g. "Night 2  1:30 to dawn".
func show_clock(text: String, night: bool) -> void:
	_clock.text = text
	_clock.modulate = Color("8b9bb4") if night else Color.WHITE


## The lobby room code, "" for none.
func show_room(code: String) -> void:
	_room.text = "Room %s" % code if code != "" else ""


## The buffs held, one line each: [text, color].
func show_buffs(lines: Array) -> void:
	for child in _buffs.get_children():
		child.queue_free()
	for line: Array in lines:
		var label := Label.new()
		label.text = line[0]
		label.modulate = line[1]
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buffs.add_child(label)


## A line at the top of the screen for a few seconds.
func announce(text: String, color := Color.WHITE) -> void:
	_announce.text = text
	_announce.modulate = color
	_announce.visible = true
	if _announce_tween:
		_announce_tween.kill()
	_announce_tween = _announce.create_tween()
	_announce_tween.tween_interval(ANNOUNCE_TIME)
	_announce_tween.tween_property(_announce, "modulate:a", 0.0, 0.6)
	_announce_tween.tween_callback(_announce.hide)


func _draw_bars() -> void:
	# Starving: the empty hunger bar blinks red.
	var empty := Color(0, 0, 0, 0.6)
	var starving := _hunger <= 0.0 and _health > 0.0 and Time.get_ticks_msec() % 1000 < 500
	for row: Array in [
		[0, _health, HEALTH_COLOR, empty],
		[BAR.y + 2, _stamina, STAMINA_COLOR, empty],
		[BAR.y * 2 + 4, _hunger, HUNGER_COLOR, Color(HEALTH_COLOR, 0.6) if starving else empty],
	]:
		var at := Vector2(0, row[0])
		_bars.draw_rect(Rect2(at, BAR), row[3])
		_bars.draw_rect(Rect2(at, Vector2(BAR.x * row[1], BAR.y)), row[2])
