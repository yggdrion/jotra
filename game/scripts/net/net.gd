# gdlint: disable=max-public-methods
# Every RPC has to live on this one node, so it outgrows the public method limit by design.
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
signal unequip_requested(peer_id: int, kind: int, to: int)
signal craft_requested(peer_id: int, recipe: StringName)
signal eat_requested(peer_id: int, index: int)
signal interact_requested(peer_id: int)
signal pinged(peer_id: int, sent_ms: int)
# Client side.
signal welcomed(spawn: Vector2, world_seed: int)
signal rejected(reason: String)
signal snapshot_received(
	players: Dictionary, enemies: Dictionary, drops: Dictionary, me: Vector4, time: float
)
signal chunk_received(coord: Vector2i, removed: PackedInt32Array)
signal prop_removed_received(coord: Vector2i, prop_id: int)
signal hit_received(enemy: bool, id: int, amount: int)
signal windup_received(enemy_id: int, seconds: float)
signal respawned_received(position: Vector2)
signal swing_received(player_id: int, heavy: bool, aim: Vector2, weapon: StringName)
signal inventory_received(data: Dictionary)
signal buffs_received(data: Dictionary)
signal looted_received(item: StringName, count: int)
signal inventory_full_received
signal room_received(code: String)
signal dungeon_received(area: Array, exit: Vector2, chest: Vector2, at: Vector2)
signal chest_opened_received
signal ponged(sent_ms: int)

## Bump on any change to the RPCs below or their payloads. Keep hello's and reject's
## signatures from here on, so a client with another version still gets the reason.
const PROTOCOL_VERSION := 11

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


## Take off what is worn in an ItemDef.Slot, into inventory slot to if it is free (-1: any).
@rpc("any_peer", "reliable")
func unequip(kind: int, to: int) -> void:
	unequip_requested.emit(multiplayer.get_remote_sender_id(), kind, to)


@rpc("any_peer", "reliable")
func craft(recipe: StringName) -> void:
	craft_requested.emit(multiplayer.get_remote_sender_id(), recipe)


## Eat one of the food in an inventory slot (-1: the first food).
@rpc("any_peer", "reliable")
func eat(index: int) -> void:
	eat_requested.emit(multiplayer.get_remote_sender_id(), index)


## E at the dungeon entrance, the run's exit or its end chest.
@rpc("any_peer", "reliable")
func interact() -> void:
	interact_requested.emit(multiplayer.get_remote_sender_id())


## The client's own clock, echoed back by pong: the round trip for the debug overlay where the
## transport has no ping of its own (WebRTC).
@rpc("any_peer", "unreliable")
func ping(sent_ms: int) -> void:
	pinged.emit(multiplayer.get_remote_sender_id(), sent_ms)


@rpc("authority", "unreliable")
func pong(sent_ms: int) -> void:
	ponged.emit(sent_ms)


@rpc("authority", "reliable")
func welcome(spawn: Vector2, world_seed: int) -> void:
	welcomed.emit(spawn, world_seed)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


## players and enemies: {id: Vector3(x, y, health 0..1)}, drops: {id: Vector3(x, y,
## Content.item_index, or -1 - the buff's index in Content.buff_ids for a buff orb)}, only
## those near the receiving player; me: its own Vector4(health, stamina, max health, hunger);
## time: the world's time, for the day/night clock.
@rpc("authority", "unreliable_ordered")
func snapshot(
	players: Dictionary, enemies: Dictionary, drops: Dictionary, me: Vector4, time: float
) -> void:
	snapshot_received.emit(players, enemies, drops, me, time)


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


## The receiving player's dungeon buffs (Buffs.to_data), whenever they change.
@rpc("authority", "reliable")
func buffs(data: Dictionary) -> void:
	buffs_received.emit(data)


## The receiving player picked something up.
@rpc("authority", "reliable")
func looted(item: StringName, count: int) -> void:
	looted_received.emit(item, count)


## The receiving player stands on loot that doesn't fit.
@rpc("authority", "reliable")
func inventory_full() -> void:
	inventory_full_received.emit()


## Player host: the lobby room code friends join with, after welcome and whenever it changes.
@rpc("authority", "reliable")
func room(code: String) -> void:
	room_received.emit(code)


## The receiving player is now at at: inside a dungeon run whose rooms and corridors are area
## (Array of Rect2), with its exit and end chest, or back in the overworld when area is empty.
@rpc("authority", "reliable")
func dungeon(area: Array, exit: Vector2, chest: Vector2, at: Vector2) -> void:
	dungeon_received.emit(area, exit, chest, at)


## The receiving player opened its run's end chest.
@rpc("authority", "reliable")
func chest_opened() -> void:
	chest_opened_received.emit()
