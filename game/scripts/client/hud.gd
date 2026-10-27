class_name Hud
extends CanvasLayer
## Health, stamina and hunger bars in the bottom-left corner with the day above them, "You
## died" in the middle while dead, announcements like nightfall at the top, a prompt for what
## the player can do right here above the bottom edge, the key panel (the main actions and
## their current keys, KeyHint.PANEL) above the day unless turned off in the settings, the
## room code friends join with in the top-right corner when hosting, the dungeon buffs held
## in the top-left one and a boss's name and health bar at the top while one is in view. The
## minimap sits in the bottom-right corner.
## A red edge closes in on the screen's border when health is low, and flashes when hit.
## Anchored to the screen, as the visible area differs per player
## (PLAN §6).

const BAR := Vector2(80, 5)
const BOSS_BAR := Vector2(160, 4)
const MARGIN := 6
const HEALTH_COLOR := Color("e43b44")
const STAMINA_COLOR := Color("feae34")
const HUNGER_COLOR := Color("b86f50")
## Seconds an announcement stays, then fades.
const ANNOUNCE_TIME := 3.0

var _bars := Control.new()
var _died := Label.new()
var _prompt := Label.new()
var _keys := GridContainer.new()
## Settings.changes when the key panel was last filled.
var _keys_seen := -1
var _clock := Label.new()
var _announce := Label.new()
var _room := Label.new()
var _buffs := VBoxContainer.new()
var _boss := Label.new()
var _status := Label.new()
var _boss_bar := Control.new()
var _boss_health := 0.0
var _health := 1.0
var _stamina := 1.0
var _hunger := 1.0
var _announce_tween: Tween
var _vignette := TextureRect.new()
## 0..1 how low health is, and a flash of red that fades.
var _low := 0.0
var _hurt := 0.0


func _ready() -> void:
	var edge := Gradient.new()
	edge.offsets = PackedFloat32Array([0.55, 1.0])
	edge.colors = PackedColorArray([Color(0.8, 0, 0, 0), Color(0.8, 0, 0, 0.75)])
	var texture := GradientTexture2D.new()
	texture.gradient = edge
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_vignette.texture = texture
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)
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
	for label: Label in [_prompt, _clock, _announce, _room, _boss, _status]:
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
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.offset_top = -24
	_status.offset_bottom = -12
	_clock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_clock.offset_left = MARGIN
	_clock.offset_bottom = -MARGIN - _bars.size.y - 1
	_clock.offset_top = _clock.offset_bottom - 12
	_keys.columns = 2
	_keys.add_theme_constant_override("h_separation", 4)
	_keys.add_theme_constant_override("v_separation", -3)
	_keys.modulate = Color(1, 1, 1, 0.7)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_keys.offset_left = MARGIN
	_keys.offset_bottom = _clock.offset_top - 2
	_keys.offset_top = _keys.offset_bottom
	add_child(_keys)
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
	_boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss.offset_top = MARGIN
	_boss.visible = false
	_boss_bar.size = BOSS_BAR
	_boss_bar.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, MARGIN + 13
	)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.draw.connect(_draw_boss_bar)
	_boss_bar.visible = false
	add_child(_boss_bar)
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
	_low = clampf(1.0 - health / Content.tuning.low_health, 0.0, 1.0) if health > 0.0 else 0.0
	_bars.queue_redraw()


## A hit just landed on the player: the red edge flashes.
func hurt() -> void:
	_hurt = 1.0


func _process(delta: float) -> void:
	if _keys_seen != Settings.changes:
		_keys_seen = Settings.changes
		_fill_keys()
	_hurt = move_toward(_hurt, 0.0, delta * 3.0)
	var beat := 0.8 + 0.2 * sin(Time.get_ticks_msec() / 160.0)
	_vignette.modulate.a = maxf(_low * beat, _hurt * 0.7)


## The key panel anew from the InputMap, or hidden if turned off.
func _fill_keys() -> void:
	_keys.visible = Settings.key_panel
	for child in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	for row: Array in KeyHint.panel_rows():
		for cell: int in 2:
			var label := Label.new()
			label.text = row[cell]
			label.add_theme_font_size_override("font_size", 8)
			label.add_theme_constant_override("outline_size", 2)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			if cell == 0:
				label.modulate = STAMINA_COLOR
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_keys.add_child(label)


## The key panel's text, for tests.
func key_panel_text() -> String:
	var cells := PackedStringArray()
	for child: Label in _keys.get_children():
		cells.append(child.text)
	return " ".join(cells) if _keys.visible else ""


## What the player can do here, e.g. "[E] Pick up stick"; "" hides it.
func show_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""


## The day and how long until it changes, e.g. "Night 2  1:30 to dawn".
func show_clock(text: String, night: bool) -> void:
	_clock.text = text
	_clock.modulate = Color("8b9bb4") if night else Color.WHITE


## The timers under the prompt, e.g. "Regen 8s  [H] Draught 12s  [Q] Frost bolt"; "" hides them.
func show_status(text: String) -> void:
	_status.text = text


## The lobby room code, "" for none.
func show_room(code: String) -> void:
	_room.text = "Room %s" % code if code != "" else ""


## The boss in view and its health 0..1; "" hides the bar.
func show_boss(boss_name: String, health: float) -> void:
	_boss.text = boss_name
	_boss.visible = boss_name != ""
	_boss_bar.visible = _boss.visible
	if health != _boss_health:
		_boss_health = health
		_boss_bar.queue_redraw()


func _draw_boss_bar() -> void:
	_boss_bar.draw_rect(Rect2(Vector2.ZERO, BOSS_BAR), Color(0, 0, 0, 0.6))
	_boss_bar.draw_rect(
		Rect2(Vector2.ZERO, Vector2(BOSS_BAR.x * _boss_health, BOSS_BAR.y)), HEALTH_COLOR
	)


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
