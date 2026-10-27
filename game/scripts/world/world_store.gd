class_name WorldStore
extends RefCounted
## The files of one world: world.json (seed, time), chunks/<x>_<y>.json (props removed from
## the seed's chunk, pieces built, graves) and players/<name>.json (position). Every write goes to a
## temp file that is renamed over the old one, so a crash mid-save leaves the previous version.
# ponytail: plain JSON files; switch this class to SQLite if file counts or save times hurt.

## Written into every file. Bump it with a migration when the format changes. 2 added pieces
## to chunks, 3 graves; older chunks read as having none.
const FORMAT_VERSION := 3

var dir: String


func _init(path: String) -> void:
	dir = ProjectSettings.globalize_path(path)


## {} for a new world, null if world.json is unreadable or from a newer server (so the
## caller stops instead of overwriting it).
func load_meta() -> Variant:
	var path := dir.path_join("world.json")
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("world: cannot read %s" % path)
		return null
	if int(data.get("version", 0)) > FORMAT_VERSION:
		push_error(
			"world: %s is format %d, this build reads %d" % [path, data.version, FORMAT_VERSION]
		)
		return null
	return data


func save_meta(data: Dictionary) -> void:
	_write("world.json", data)


## {removed: PackedInt32Array of prop ids, pieces and graves: Arrays of what save_chunk was
## given}.
func load_chunk(coord: Vector2i) -> Dictionary:
	var data := _read(_chunk_file(coord))
	return {
		removed = PackedInt32Array(data.get("removed", [])),
		pieces = data.get("pieces", []),
		graves = data.get("graves", []),
	}


## pieces and graves: one Dictionary per piece built and grave lying in the chunk, as SimWorld
## writes them.
func save_chunk(coord: Vector2i, removed: PackedInt32Array, pieces := [], graves := []) -> void:
	_write(_chunk_file(coord), {removed = Array(removed), pieces = pieces, graves = graves})


## {} for a player never saved here.
func load_player(player_name: String) -> Dictionary:
	return _read("players/%s.json" % player_name)


func save_player(player_name: String, data: Dictionary) -> void:
	_write("players/%s.json" % player_name, data)


static func _chunk_file(coord: Vector2i) -> String:
	return "chunks/%d_%d.json" % [coord.x, coord.y]


# ponytail: an unreadable chunk or player file counts as empty and gets overwritten; writes are
# atomic, so only outside damage gets there.
func _read(file: String) -> Dictionary:
	var path := dir.path_join(file)
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("world: cannot read %s" % path)
		return {}
	return data


func _write(file: String, data: Dictionary) -> void:
	var path := dir.path_join(file)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var out := data.duplicate()
	out.version = FORMAT_VERSION
	var tmp := path + ".tmp"
	var handle := FileAccess.open(tmp, FileAccess.WRITE)
	if handle == null:
		push_error("world: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	handle.store_string(JSON.stringify(out))
	handle.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("world: cannot replace %s (%s)" % [path, error_string(err)])
