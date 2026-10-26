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
signal item_moved(peer_id: int, from: int, to: int)
signal equip_requested(peer_id: int, index: int)
signal unequip_requested(peer_id: int, kind: int)
signal craft_requested(peer_id: int, recipe: StringName)
# Client side.
signal welcomed(spawn: Vector2, world_seed: int)
signal rejected(reason: String)
signal snapshot_received(players: Dictionary, enemies: Dictionary, drops: Dictionary, me: Vector3)
signal chunk_received(coord: Vector2i, removed: PackedInt32Array)
signal prop_removed_received(coord: Vector2i, prop_id: int)
signal hit_received(enemy: bool, id: int, amount: int)
signal windup_received(enemy_id: int, seconds: float)
signal respawned_received(position: Vector2)
signal swing_received(player_id: int, heavy: bool, aim: Vector2, weapon: StringName)
signal inventory_received(data: Dictionary)
signal looted_received(item: StringName, count: int)

## Bump on any change to the RPCs below or their payloads. Keep hello's and reject's
## signatures from here on, so a client with another version still gets the reason.
const PROTOCOL_VERSION := 5

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


## Inventory slot from onto slot to (merge or swap).
@rpc("any_peer", "reliable")
func move_item(from: int, to: int) -> void:
	item_moved.emit(multiplayer.get_remote_sender_id(), from, to)


## Wear the item in an inventory slot.
@rpc("any_peer", "reliable")
func equip(index: int) -> void:
	equip_requested.emit(multiplayer.get_remote_sender_id(), index)


## Take off what is worn in an ItemDef.Slot.
@rpc("any_peer", "reliable")
func unequip(kind: int) -> void:
	unequip_requested.emit(multiplayer.get_remote_sender_id(), kind)


@rpc("any_peer", "reliable")
func craft(recipe: StringName) -> void:
	craft_requested.emit(multiplayer.get_remote_sender_id(), recipe)


@rpc("authority", "reliable")
func welcome(spawn: Vector2, world_seed: int) -> void:
	welcomed.emit(spawn, world_seed)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


## players and enemies: {id: Vector3(x, y, health 0..1)}, drops: {id: Vector3(x, y,
## Content.item_index)}, only those near the receiving player; me: its own Vector3(health,
## stamina, max health).
@rpc("authority", "unreliable_ordered")
func snapshot(players: Dictionary, enemies: Dictionary, drops: Dictionary, me: Vector3) -> void:
	snapshot_received.emit(players, enemies, drops, me)


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


## An enemy in view started an attack that lands in seconds: the telegraph to dash from.
@rpc("authority", "reliable")
func windup(enemy_id: int, seconds: float) -> void:
	windup_received.emit(enemy_id, seconds)


## Another player in view swung weapon (or "" bare-handed): draw it.
@rpc("authority", "reliable")
func swing(player_id: int, heavy: bool, aim: Vector2, weapon: StringName) -> void:
	swing_received.emit(player_id, heavy, aim, weapon)


## The receiving player died earlier and is back, here.
@rpc("authority", "reliable")
func respawned(position: Vector2) -> void:
	respawned_received.emit(position)


## The receiving player's whole inventory (Inventory.to_data), on joining and after changes.
@rpc("authority", "reliable")
func inventory(data: Dictionary) -> void:
	inventory_received.emit(data)


## The receiving player picked something up.
@rpc("authority", "reliable")
func looted(item: StringName, count: int) -> void:
	looted_received.emit(item, count)
