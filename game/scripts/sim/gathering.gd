class_name Gathering
## Swinging at trees and rocks: the closest one in a swing's arc loses health to the best
## carried axe or pickaxe and falls at 0.


## A swing that hit no enemy takes health off the closest tree or rock in its arc, felling it
## at 0 (the loot drops). With no tool, or too low a tier, it only tells the swinger.
static func swing(
	world: SimWorld, player: SimWorld.SimPlayer, aim: Vector2, reach: float, arc: float
) -> void:
	var best_distance := INF
	var best_coord := Vector2i.ZERO
	var best_id := -1
	for coord in WorldGen.around(WorldGen.chunk_of(player.position), 1):
		var chunk: SimWorld.SimChunk = world.chunks.get(coord)
		if chunk == null:
			continue
		for prop_id: int in chunk.props:
			if not WorldGen.is_node(chunk.props[prop_id]) or chunk.removed.has(prop_id):
				continue
			var at := WorldGen.prop_position(coord, prop_id)
			var distance := player.position.distance_to(at)
			if distance < best_distance and Combat.in_arc(player.position, aim, at, reach, arc):
				best_distance = distance
				best_coord = coord
				best_id = prop_id
	if best_id == -1:
		return
	var chunk: SimWorld.SimChunk = world.chunks[best_coord]
	var at := WorldGen.prop_position(best_coord, best_id)
	var t := Content.tuning
	var tree: bool = chunk.props[best_id] == WorldGen.Prop.TREE
	var tool := player.inventory.best_tool(ItemDef.Tool.AXE if tree else ItemDef.Tool.PICKAXE)
	var noun := "axe" if tree else "pickaxe"
	if tool == null:
		world.events.append(["node", player.id, at, "Needs a%s %s" % ["n" if tree else "", noun]])
		return
	if tool.tool_tier < (t.tree_tier if tree else t.rock_tier):
		world.events.append(["node", player.id, at, "Needs a better %s" % noun])
		return
	var left: float = (
		chunk.node_health.get(best_id, t.tree_health if tree else t.rock_health) - tool.tool_damage
	)
	world.events.append(["node", player.id, at, str(roundi(tool.tool_damage))])
	if left > 0:
		chunk.node_health[best_id] = left
		return
	chunk.node_health.erase(best_id)
	_remove(world, chunk, best_coord, best_id)
	world._drop_loot(t.tree_drops if tree else t.rock_drops, at)


## Picks up the stick or pebble a player stands next to, at most one per gather_time (the
## server's SimWorld.remove_prop). Returns whether it did.
static func pick_up(world: SimWorld, id: int, coord: Vector2i, prop_id: int) -> bool:
	var player: SimWorld.SimPlayer = world.players.get(id)
	var chunk: SimWorld.SimChunk = world.chunks.get(coord)
	if player == null or chunk == null or player.dead_until > 0:
		return false
	if world.time - player.gathered_at < Content.tuning.gather_time:
		return false
	if not chunk.props.has(prop_id) or chunk.removed.has(prop_id):
		return false
	if WorldGen.is_node(chunk.props[prop_id]):
		return false
	var at := WorldGen.prop_position(coord, prop_id)
	if player.position.distance_to(at) > SimWorld.REACH + SimWorld.REACH_SLACK:
		return false
	_remove(world, chunk, coord, prop_id)
	player.gathered_at = world.time
	var t := Content.tuning
	var table: Array = (
		t.stick_drops if chunk.props[prop_id] == WorldGen.Prop.STICK else t.pebble_drops
	)
	world._drop_loot(table, at)
	return true


static func _remove(
	world: SimWorld, chunk: SimWorld.SimChunk, coord: Vector2i, prop_id: int
) -> void:
	chunk.removed[prop_id] = true
	chunk.dirty = true
	world.events.append(["prop_removed", coord, prop_id])
