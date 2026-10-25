class_name Net
extends Node
## The one node both sides talk through, at /root/Main/Net on server and client so the RPCs
## line up. GameServer and GameClient call the RPCs and listen to the signals.

# Server side.
signal hello_received(peer_id: int, version: int, player_name: String)
signal moved(peer_id: int, position: Vector2)
signal prop_remove_requested(peer_id: int, coord: Vector2i, prop_id: int)
# Client side.
signal welcomed(spawn: Vector2, world_seed: int)
signal rejected(reason: String)
signal snapshot_received(players: Dictionary)
signal chunk_received(coord: Vector2i, removed: PackedInt32Array)
signal prop_removed_received(coord: Vector2i, prop_id: int)

## Bump on any change to the RPCs below or their payloads. Keep hello's and reject's
## signatures from here on, so a client with another version still gets the reason.
const PROTOCOL_VERSION := 2

@rpc("any_peer", "reliable")
func hello(version: int, player_name: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), version, player_name)


@rpc("any_peer", "unreliable_ordered")
func move(position: Vector2) -> void:
	moved.emit(multiplayer.get_remote_sender_id(), position)


@rpc("any_peer", "reliable")
func remove_prop(coord: Vector2i, prop_id: int) -> void:
	prop_remove_requested.emit(multiplayer.get_remote_sender_id(), coord, prop_id)


@rpc("authority", "reliable")
func welcome(spawn: Vector2, world_seed: int) -> void:
	welcomed.emit(spawn, world_seed)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


## players: {peer_id: position}, only those near the receiving player.
@rpc("authority", "unreliable_ordered")
func snapshot(players: Dictionary) -> void:
	snapshot_received.emit(players)


## A chunk entered the player's view: the client generates it from the seed and leaves out
## the removed props.
@rpc("authority", "reliable")
func chunk(coord: Vector2i, removed: PackedInt32Array) -> void:
	chunk_received.emit(coord, removed)


@rpc("authority", "reliable")
func prop_removed(coord: Vector2i, prop_id: int) -> void:
	prop_removed_received.emit(coord, prop_id)
