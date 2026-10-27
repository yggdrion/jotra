class_name CharacterList
extends RefCounted
## The player's characters, kept on this machine in user://characters.json: a name (the name the
## worlds save the player by, so the same character has its own progress in each world), a look
## (Net.player_z) and a starting kit (KitDef id). The start menu lists, creates and deletes them
## here and remembers the last one played.

const PATH := "user://characters.json"


## [{name, look, kit}] in the order they were made.
static func list(path := PATH) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in _read(path).get("characters", []):
		if entry is Dictionary and valid_name(str(entry.get("name", ""))):
			(
				out
				. append(
					{
						name = str(entry.name),
						look = clampi(int(entry.get("look", 0)), 0, Net.LOOKS - 1),
						kit = StringName(str(entry.get("kit", ""))),
					}
				)
			)
	return out


## The same rule as the server's for player names: 1-32 letters, digits, - or _.
static func valid_name(character_name: String) -> bool:
	return RegEx.create_from_string("^[A-Za-z0-9_-]{1,32}$").search(character_name) != null


## Makes a character. "" if done, else why not.
static func create(character_name: String, look: int, kit: StringName, path := PATH) -> String:
	if not valid_name(character_name):
		return "Names are 1-32 letters, digits, - or _"
	if list(path).any(func(c: Dictionary) -> bool: return c.name == character_name):
		return "A character called %s exists" % character_name
	if kit != &"" and not Content.kits.has(kit):
		return "Pick a starting kit"
	var data := _read(path)
	var characters: Array = data.get("characters", [])
	characters.append({name = character_name, look = look, kit = str(kit)})
	data.characters = characters
	data.last = character_name
	_write(path, data)
	return ""


## Forgets a character on this machine; the worlds keep what they saved of it.
static func delete(character_name: String, path := PATH) -> void:
	var data := _read(path)
	var characters: Array = data.get("characters", [])
	data.characters = characters.filter(
		func(c: Variant) -> bool: return not (c is Dictionary and c.get("name") == character_name)
	)
	_write(path, data)


## The character played last, or the first one, or {} if there is none.
static func last(path := PATH) -> Dictionary:
	var characters := list(path)
	var name: String = _read(path).get("last", "")
	for c in characters:
		if c.name == name:
			return c
	return characters[0] if not characters.is_empty() else {}


static func remember(character_name: String, path := PATH) -> void:
	var data := _read(path)
	data.last = character_name
	_write(path, data)


static func _read(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


static func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
