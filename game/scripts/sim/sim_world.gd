class_name SimWorld
extends RefCounted
## The server's simulation. Plain objects, no scene tree: tests build one directly and step it
## with tick(delta); GameServer drives the same path.


class SimPlayer:
	var id: int
	var position: Vector2
	## Sim time of the last accepted move, for the speed check.
	var moved_at: float

	func _init(player_id: int, spawn: Vector2, now: float) -> void:
		id = player_id
		position = spawn
		moved_at = now


## Player walk speed in px/s. Client movement uses the same number.
# ponytail: one constant until M3 moves gameplay numbers into .tres data.
const MAX_SPEED := 120.0
## Extra time allowed per move, so packets that arrive bunched up still pass.
const MOVE_SLACK := 0.5
const SPAWN_SPACING := 24.0

var time := 0.0
var players := {}  # id -> SimPlayer


## Paused while nobody is online: time stands still.
func tick(delta: float) -> void:
	if players.is_empty():
		return
	time += delta


func add_player(id: int) -> SimPlayer:
	var player := SimPlayer.new(id, Vector2(players.size() * SPAWN_SPACING, 0), time)
	players[id] = player
	return player


func remove_player(id: int) -> void:
	players.erase(id)


## Client-authoritative movement with a basic sanity check: a move further than the walk speed
## allows (plus slack) is a teleport and is dropped. Returns whether it was accepted.
# ponytail: no correction sent back; a dropped move only holds the server copy until the next one.
func move_player(id: int, position: Vector2) -> bool:
	var player: SimPlayer = players.get(id)
	if player == null:
		return false
	var allowed := MAX_SPEED * (time - player.moved_at + MOVE_SLACK)
	if player.position.distance_to(position) > allowed:
		return false
	player.position = position
	player.moved_at = time
	return true


## {id: position} of every player, as sent to clients.
func snapshot() -> Dictionary:
	var out := {}
	for id: int in players:
		out[id] = players[id].position
	return out
