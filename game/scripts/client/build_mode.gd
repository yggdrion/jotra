class_name BuildMode
extends Node2D
## Build mode (B): a ghost of the chosen piece on the tile under the mouse, green where it can be
## built (or repaired) and red where not, and the HUD line for it. GameClient turns the clicks
## into requests; the BuildMenu (shown with it), 1-6 for its hotbar or the mouse wheel choose
## the piece.

const GOOD := Color(0.4, 0.9, 0.4, 0.6)
const BAD := Color(0.9, 0.25, 0.25, 0.6)
const REASONS := {
	Building.Status.OK: "",
	Building.Status.REPAIR: "Repair",
	Building.Status.FAR: "Too far",
	Building.Status.PROP: "Something stands there",
	Building.Status.TAKEN: "Already built on",
	Building.Status.IN_THE_WAY: "Someone is in the way",
	Building.Status.MISSING_ITEMS: "Missing items",
}

var selected := 0
## The tile under the mouse and whether the chosen piece can go there.
var tile := Vector2i.ZERO
var status := Building.Status.OK
var _ghost := PieceView.new()
var _menu := BuildMenu.new()


func _ready() -> void:
	visible = false
	z_index = 5
	_ghost.ghost = GOOD
	add_child(_ghost)
	add_child(_menu)
	_menu.picked.connect(func(id: StringName) -> void: select(Content.piece_ids.find(id)))
	_menu.choose(piece_id())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_menu.visible = visible


## Chooses the piece on a hotbar slot (0-5), if there is one.
func select_slot(slot: int) -> void:
	var id := _menu.hotbar_piece(slot)
	if id != &"":
		select(Content.piece_ids.find(id))


func piece_id() -> StringName:
	return Content.piece_ids[selected]


## By index into Content.piece_ids, wrapping around.
func select(index: int) -> void:
	selected = posmod(index, Content.piece_ids.size())
	_menu.choose(piece_id())


## Puts the ghost on the tile under mouse and checks the chosen piece there, hiding it while the
## mouse is over the menu; chunks are the client's ChunkViews, for the props.
func update(
	mouse: Vector2,
	pieces: Dictionary,
	chunks: Dictionary,
	inventory: Inventory,
	at: Vector2,
	bodies: Array[Vector2]
) -> void:
	_menu.refresh(inventory)
	tile = Building.tile_of(mouse)
	var chunk: ChunkView = chunks.get(Building.chunk_of_tile(tile))
	var prop := chunk == null or chunk.has_prop(Building.index_in_chunk(tile))
	status = Building.can_build(pieces, tile, piece_id(), inventory, at, prop, bodies)
	_ghost.position = Building.tile_center(tile)
	_ghost.ghost = GOOD if status in [Building.Status.OK, Building.Status.REPAIR] else BAD
	if _ghost.piece == null or _ghost.piece.id != piece_id():
		_ghost.piece = Building.Piece.new(piece_id())
	_ghost.mask = Building.join_mask(pieces, tile, piece_id())
	_ghost.visible = not _menu.has_mouse()


## The chosen piece, its cost against what the inventory holds, why it can't go here, and the
## controls.
func prompt(inventory: Inventory) -> String:
	var def := Content.piece(piece_id())
	var costs := PackedStringArray()
	for item: StringName in def.cost:
		var name := Content.item(item).display_name.to_lower()
		costs.append("%d %s (%d)" % [def.cost[item], name, inventory.count_of(item)])
	var reason: String = REASONS[status]
	return (
		"%s: %s%s   [LMB] build  [RMB] remove  [1-%d] hotbar  %s done"
		% [
			def.display_name,
			", ".join(costs),
			"  - " + reason if reason != "" else "",
			BuildMenu.HOTBAR,
			KeyHint.tag(&"build"),
		]
	)
