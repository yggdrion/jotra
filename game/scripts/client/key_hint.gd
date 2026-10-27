class_name KeyHint
extends RefCounted
## The keys on-screen text names, read off the InputMap so a rebind in the settings menu shows
## everywhere: key(&"interact") is "E", or whatever the player bound it to.

## The main actions for the HUD's key panel: [keys, what they do]. Swings are fixed on the mouse.
const PANEL := [
	[[&"move_up", &"move_left", &"move_down", &"move_right"], "Move"],
	["LMB / RMB", "Light / heavy swing"],
	[[&"dash"], "Dash"],
	[[&"interact"], "Use / gather"],
	[[&"eat"], "Eat"],
	[[&"heal"], "Draught"],
	[[&"ability"], "Rune ability"],
	[[&"inventory"], "Inventory"],
	[[&"build"], "Build"],
	[[&"character"], "Character"],
	[[&"map"], "Map"],
]


## The display name of an action's first binding, a key or a mouse button; "?" if unbound.
static func key(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		var name := event_name(event)
		if name != "":
			return name
	return "?"


## "[E]" for &"interact".
static func tag(action: StringName) -> String:
	return "[%s]" % key(action)


static func event_name(event: InputEvent) -> String:
	var pressed := event as InputEventKey
	if pressed:
		var code := pressed.physical_keycode if pressed.physical_keycode else pressed.keycode
		return OS.get_keycode_string(code)
	var mouse := event as InputEventMouseButton
	if mouse:
		match mouse.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel down"
			_:
				return "Mouse %d" % mouse.button_index
	return ""


## The key panel's rows: [keys, what they do], e.g. ["WASD", "Move"] or ["E", "Use / gather"].
static func panel_rows() -> Array:
	var rows := []
	for row: Array in PANEL:
		var keys: String = row[0] if row[0] is String else _joined(row[0])
		rows.append([keys, row[1]])
	return rows


## Single-character keys run together (WASD), longer ones get a slash (Up/Left/Down/Right).
static func _joined(actions: Array) -> String:
	var names := PackedStringArray()
	var short := true
	for action: StringName in actions:
		names.append(key(action))
		short = short and names[-1].length() == 1
	return "".join(names) if short else "/".join(names)
