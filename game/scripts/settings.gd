class_name Settings
extends RefCounted
## What the player sets in the settings menu, kept in user://settings.cfg: Master volume,
## fullscreen, screenshake strength, whether the HUD shows its key panel and the keys of the
## InputMap actions in ACTIONS. apply() puts it all in force.

const PATH := "user://settings.cfg"
## action: [label, default physical keys]. Escape, 1-9 and F3/F11 are fixed.
const ACTIONS := {
	&"move_up": ["Move up", [KEY_W]],
	&"move_down": ["Move down", [KEY_S]],
	&"move_left": ["Move left", [KEY_A]],
	&"move_right": ["Move right", [KEY_D]],
	&"interact": ["Use / gather", [KEY_E]],
	&"dash": ["Dash", [KEY_SPACE]],
	&"eat": ["Eat", [KEY_F]],
	&"heal": ["Healing draught", [KEY_H]],
	&"ability": ["Rune ability", [KEY_Q]],
	&"inventory": ["Inventory", [KEY_TAB, KEY_I]],
	&"character": ["Character", [KEY_C]],
	&"build": ["Build", [KEY_B]],
	&"map": ["Map", [KEY_M]],
}

static var volume := 1.0
static var fullscreen := true
## Share of the full screenshake, 0 for none.
static var shake := 0.5
static var key_panel := true
## Goes up on every apply(), so screens showing keys know to redraw them.
static var changes := 0
## {action: key} the player rebound; actions not in it use their defaults.
static var keys := {}


static func load_file() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	volume = clampf(float(file.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	fullscreen = bool(file.get_value("video", "fullscreen", true))
	shake = clampf(float(file.get_value("video", "shake", 0.5)), 0.0, 1.0)
	key_panel = bool(file.get_value("hud", "key_panel", true))
	for action: StringName in ACTIONS:
		var key := int(file.get_value("keys", action, 0))
		if key != 0:
			keys[action] = key


static func save_file() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "volume", volume)
	file.set_value("video", "fullscreen", fullscreen)
	file.set_value("video", "shake", shake)
	file.set_value("hud", "key_panel", key_panel)
	for action: StringName in keys:
		file.set_value("keys", action, keys[action])
	file.save(PATH)


## The keys an action answers to now.
static func keys_of(action: StringName) -> Array:
	return [keys[action]] if keys.has(action) else ACTIONS[action][1]


## Volume and the InputMap; the window mode is left to the caller, who knows --windowed.
static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		for key: int in keys_of(action):
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)
	changes += 1


## The action another action's key clashes with, &"" if free.
static func clash(action: StringName, key: int) -> StringName:
	for other: StringName in ACTIONS:
		if other != action and key in keys_of(other):
			return other
	return &""


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)
