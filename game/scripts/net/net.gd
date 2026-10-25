class_name Net
extends Node
## The one node both sides talk through, at /root/Main/Net on server and client so the RPCs
## line up. GameServer and GameClient call the RPCs and listen to the signals.

# Server side.
signal hello_received(peer_id: int, version: int)
signal moved(peer_id: int, position: Vector2)
# Client side.
signal welcomed(spawn: Vector2)
signal rejected(reason: String)
signal snapshot_received(players: Dictionary)

## Bump on any change to the RPCs below or their payloads.
const PROTOCOL_VERSION := 1

@rpc("any_peer", "reliable")
func hello(version: int) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), version)


@rpc("any_peer", "unreliable_ordered")
func move(position: Vector2) -> void:
	moved.emit(multiplayer.get_remote_sender_id(), position)


@rpc("authority", "reliable")
func welcome(spawn: Vector2) -> void:
	welcomed.emit(spawn)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


## players: {peer_id: position}
@rpc("authority", "unreliable_ordered")
func snapshot(players: Dictionary) -> void:
	snapshot_received.emit(players)
