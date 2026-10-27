extends GdUnitTestSuite
## KeyHint reads the InputMap, so hints and the HUD's key panel follow a rebind.

var _keys := {}
var _key_panel := true


func before_test() -> void:
	_keys = Settings.keys.duplicate()
	_key_panel = Settings.key_panel


func after_test() -> void:
	Settings.keys = _keys
	Settings.key_panel = _key_panel
	Settings.apply()


func test_names_the_first_binding_and_follows_a_rebind() -> void:
	Settings.keys.erase(&"interact")
	Settings.keys.erase(&"inventory")
	Settings.apply()
	assert_str(KeyHint.key(&"interact")).is_equal("E")
	assert_str(KeyHint.tag(&"interact")).is_equal("[E]")
	assert_str(KeyHint.key(&"inventory")).is_equal("Tab")
	Settings.keys[&"interact"] = KEY_G
	Settings.apply()
	assert_str(KeyHint.key(&"interact")).is_equal("G")


func test_mouse_buttons_and_unbound_actions() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	assert_str(KeyHint.event_name(click)).is_equal("RMB")
	assert_str(KeyHint.key(&"no_such_action")).is_equal("?")


func test_panel_rows_join_movement_and_follow_settings() -> void:
	for action: StringName in [&"move_up", &"move_left", &"move_down", &"move_right"]:
		Settings.keys.erase(action)
	Settings.keys[&"dash"] = KEY_SHIFT
	Settings.apply()
	var rows := KeyHint.panel_rows()
	assert_array(rows[0]).is_equal(["WASD", "Move"])
	assert_array(rows).contains([["Shift", "Dash"]])
	Settings.keys[&"move_up"] = KEY_UP
	Settings.apply()
	assert_str(KeyHint.panel_rows()[0][0]).is_equal("Up/A/S/D")


func test_hud_panel_redraws_on_settings_change_and_hides() -> void:
	Settings.keys[&"map"] = KEY_N
	Settings.apply()
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	await await_idle_frame()
	assert_str(hud.key_panel_text()).contains("N Map")
	Settings.keys[&"map"] = KEY_COMMA
	Settings.key_panel = false
	Settings.apply()
	await await_idle_frame()
	assert_str(hud.key_panel_text()).is_equal("")
	Settings.key_panel = true
	Settings.apply()
	await await_idle_frame()
	assert_str(hud.key_panel_text()).contains("Comma Map")
