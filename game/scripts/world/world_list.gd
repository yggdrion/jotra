class_name WorldList
extends RefCounted
## The solo worlds under one directory (user://worlds): one subdirectory each, holding the
## world.json that SimWorld.open reads. The start menu lists, creates and deletes them here.

const ROOT := "user://worlds"


## [{name, seed}] sorted by name; only directories with a readable world.json count.
static func list(root := ROOT) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names := DirAccess.get_directories_at(root)
	names.sort()
	for world_name in names:
		var meta: Variant = WorldStore.new(root.path_join(world_name)).load_meta()
		if meta is Dictionary and meta.has("seed"):
			out.append({name = world_name, seed = int(meta.seed)})
	return out


## Letters, digits, space, dash and underscore, at most 24, so it is safe as a directory name.
static func valid_name(world_name: String) -> bool:
	var re := RegEx.create_from_string("^[A-Za-z0-9_-][A-Za-z0-9 _-]{0,23}$")
	return re.search(world_name) != null and world_name == world_name.strip_edges()


## Makes a world with this seed. "" if done, else why not.
static func create(world_name: String, world_seed: int, root := ROOT) -> String:
	if not valid_name(world_name):
		return "Names are 1-24 letters, digits, spaces, - or _"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root.path_join(world_name))):
		return "A world called %s exists" % world_name
	WorldStore.new(root.path_join(world_name)).save_meta({seed = world_seed, time = 0.0})
	return ""


## Removes the world's directory with everything in it.
static func delete(world_name: String, root := ROOT) -> void:
	if valid_name(world_name):
		_remove(ProjectSettings.globalize_path(root.path_join(world_name)))


static func _remove(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
