class_name Net
extends Node
## The one node both sides talk through, at /root/Main/Net on server and client so the RPCs
## line up. GameServer and GameClient call the RPCs and listen to the signals.

# Server side.
signal hello_received(peer_id: int, version: int, player_name: String)
signal moved(peer_id: int, position: Vector2)
signal prop_remove_requested(peer_id: int, coord: Vector2i, prop_id: int)
signal attacked(peer_id: int, heavy: bool, aim: Vector2, hits: PackedInt32Array)
signal dashed(peer_id: int)
# Client side.
signal welcomed(spawn: Vector2, world_seed: int)
signal rejected(reason: String)
signal snapshot_received(players: Dictionary, enemies: Dictionary, me: Vector2)
signal chunk_received(coord: Vector2i, removed: PackedInt32Array)
signal prop_removed_received(coord: Vector2i, prop_id: int)
signal hit_received(enemy: bool, id: int, amount: int)
signal windup_received(enemy_id: int)
signal respawned_received(position: Vector2)
signal swing_received(player_id: int, heavy: bool, aim: Vector2)

## Bump on any change to the RPCs below or their payloads. Keep hello's and reject's
## signatures from here on, so a client with another version still gets the reason.
const PROTOCOL_VERSION := 4

@rpc("any_peer", "reliable")
func hello(version: int, player_name: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), version, player_name)


@rpc("any_peer", "unreliable_ordered")
func move(position: Vector2) -> void:
	moved.emit(multiplayer.get_remote_sender_id(), position)


@rpc("any_peer", "reliable")
func remove_prop(coord: Vector2i, prop_id: int) -> void:
	prop_remove_requested.emit(multiplayer.get_remote_sender_id(), coord, prop_id)


## A swing toward aim, with the enemies the client saw it hit.
@rpc("any_peer", "reliable")
func attack(heavy: bool, aim: Vector2, hits: PackedInt32Array) -> void:
	attacked.emit(multiplayer.get_remote_sender_id(), heavy, aim, hits)


@rpc("any_peer", "reliable")
func dash() -> void:
	dashed.emit(multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func welcome(spawn: Vector2, world_seed: int) -> void:
	welcomed.emit(spawn, world_seed)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


## players and enemies: {id: Vector3(x, y, health 0..1)}, only those near the receiving player;
## me: its own Vector2(health, stamina).
@rpc("authority", "unreliable_ordered")
func snapshot(players: Dictionary, enemies: Dictionary, me: Vector2) -> void:
	snapshot_received.emit(players, enemies, me)


## A chunk entered the player's view: the client generates it from the seed and leaves out
## the removed props.
@rpc("authority", "reliable")
func chunk(coord: Vector2i, removed: PackedInt32Array) -> void:
	chunk_received.emit(coord, removed)


@rpc("authority", "reliable")
func prop_removed(coord: Vector2i, prop_id: int) -> void:
	prop_removed_received.emit(coord, prop_id)


## An enemy or player in view took damage: flash and damage number.
@rpc("authority", "reliable")
func hit(enemy: bool, id: int, amount: int) -> void:
	hit_received.emit(enemy, id, amount)


## An enemy in view started an attack: the telegraph to dash from.
@rpc("authority", "reliable")
func windup(enemy_id: int) -> void:
	windup_received.emit(enemy_id)


## Another player in view swung: draw it.
@rpc("authority", "reliable")
func swing(player_id: int, heavy: bool, aim: Vector2) -> void:
	swing_received.emit(player_id, heavy, aim)


## The receiving player died earlier and is back, here.
@rpc("authority", "reliable")
func respawned(position: Vector2) -> void:
	respawned_received.emit(position)
