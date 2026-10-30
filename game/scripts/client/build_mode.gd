class_name BuildMode
extends Node2D
## Build mode (B): a ghost of the chosen piece on the tile under the mouse, green where it can be
## built (or repaired) and red where not, a ring around the player for the build reach, and the
## HUD line for it. GameClient turns the clicks
## into requests; the BuildMenu (shown with it), 1-6 for its hotbar or the mouse wheel choose
## the piece.

const GOOD := Color(0.4, 0.9, 0.4, 0.6)
const BAD := Color(0.9, 0.25, 0.25, 0.6)
const RING := Color(1, 1, 1, 0.25)
const REASONS := {
	Building.Status.OK: "",
	Building.Status.REPAIR: "Repair",
	Building.Status.FAR: "Out of reach",
	Building.Status.PROP: "Blocked by a prop",
	Building.Status.CLIFF: "Blocked by a cliff",
	Building.Status.TAKEN: "Blocked by another piece",
	Building.Status.IN_THE_WAY: "Blocked by a player or enemy",
	Building.Status.MISSING_ITEMS: "Missing items",
	Building.Status.UNAVAILABLE: "Can't build here",
}

var selected := 0
## The tile under the mouse and whether the chosen piece can go there.
var tile := Vector2i.ZERO
var status := Building.Status.OK
## Where the player stands, the center of the reach ring.
var _at := Vector2.ZERO
var _ghost := PieceView.new()
var _menu := BuildMenu.new()
var _rejected_tile := Vector2i.ZERO
var _rejected_piece: StringName = &""
var _rejected_status := Building.Status.UNAVAILABLE
var _rejected_until := 0


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
	var index := Building.index_in_chunk(tile)
	var prop := chunk == null or chunk.has_prop(index) or tile == Building.portal_tile()
	var cliff := chunk != null and chunk.is_cliff(index)
	status = Building.can_build(pieces, tile, piece_id(), inventory, at, prop, bodies, 0.0, cliff)
	if (
		tile == _rejected_tile
		and piece_id() == _rejected_piece
		and Time.get_ticks_msec() < _rejected_until
	):
		status = _rejected_status
	_ghost.position = Building.tile_center(tile)
	_ghost.ghost = GOOD if status in [Building.Status.OK, Building.Status.REPAIR] else BAD
	if _ghost.piece == null or _ghost.piece.id != piece_id():
		_ghost.piece = Building.Piece.new(piece_id())
	_ghost.mask = Building.join_mask(pieces, tile, piece_id())
	_ghost.visible = not _menu.has_mouse()
	if at != _at:
		_at = at
		queue_redraw()


## Shows an authoritative server rejection briefly, even if the client's preview was green.
func reject(tile_at: Vector2i, piece: StringName, reason: int) -> void:
	_rejected_tile = tile_at
	_rejected_piece = piece
	_rejected_status = reason
	_rejected_until = Time.get_ticks_msec() + 900


func _draw() -> void:
	draw_arc(_at, Content.tuning.build_reach, 0, TAU, 48, RING, 1.0)


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
