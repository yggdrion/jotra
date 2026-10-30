extends SceneTree

const MANIFEST_PATH := "res://assets/manifest.json"


func _initialize() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_fail("Cannot open %s" % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("assets") is Array:
		_fail("Manifest must have version 1 and an assets array")
		return

	var errors: Array[String] = []
	var ids := {}
	for entry in parsed.assets:
		if not entry is Dictionary:
			errors.append("Asset entry must be an object")
			continue
		_validate_entry(entry, ids, errors)

	if errors.is_empty():
		print("Asset manifest valid: %d assets" % parsed.assets.size())
		quit(0)
	else:
		for error in errors:
			push_error(error)
		quit(1)


func _validate_entry(entry: Dictionary, ids: Dictionary, errors: Array[String]) -> void:
	var id := str(entry.get("id", ""))
	var path := str(entry.get("path", ""))
	if id.is_empty() or ids.has(id):
		errors.append("Asset id is missing or duplicated: %s" % id)
	else:
		ids[id] = true
	if not ["candidate", "approved", "rejected"].has(entry.get("status")):
		errors.append("%s: status must be candidate, approved, or rejected" % id)
	if not path.begins_with("assets/") or path.contains(".."):
		errors.append("%s: path must stay inside res://assets" % id)
		return
	var full_path := "res://" + path
	if not FileAccess.file_exists(full_path):
		errors.append("%s: missing file %s" % [id, full_path])
		return
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(full_path))
	if load_error != OK:
		errors.append("%s: image could not be loaded (%s)" % [id, error_string(load_error)])
		return
	var width_mismatch := image.get_width() != int(entry.get("width", -1))
	var height_mismatch := image.get_height() != int(entry.get("height", -1))
	if width_mismatch or height_mismatch:
		var size := "%d x %d" % [image.get_width(), image.get_height()]
		errors.append("%s: declared dimensions do not match image (%s)" % [id, size])
	var frame_width := int(entry.get("frame_width", 0))
	var frame_height := int(entry.get("frame_height", 0))
	if frame_width > 0 or frame_height > 0:
		var bad_frame_size := frame_width <= 0 or frame_height <= 0
		var width_not_divisible := frame_width > 0 and image.get_width() % frame_width != 0
		var height_not_divisible := frame_height > 0 and image.get_height() % frame_height != 0
		if bad_frame_size or width_not_divisible or height_not_divisible:
			errors.append("%s: frame dimensions must divide the image dimensions" % id)
	if entry.get("alpha", false) and not image.has_alpha():
		errors.append("%s: transparency is required but image has no alpha channel" % id)
	for reference in entry.get("references", []):
		if not FileAccess.file_exists("res://" + str(reference)):
			errors.append("%s: missing reference %s" % [id, reference])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
