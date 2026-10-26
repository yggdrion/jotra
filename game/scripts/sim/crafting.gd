class_name Crafting
## Turning items into others by a RecipeDef, by hand or at a station (Tuning.stations).

## Why a recipe can or can't be crafted right now; the client shows it next to the recipe.
enum Status { READY, AWAY_FROM_STATION, MISSING_ITEMS, NO_ROOM }


## Crafts a recipe if the player is alive and its status is READY. Returns whether it did.
static func craft(player: SimWorld.SimPlayer, recipe_id: StringName) -> bool:
	var recipe: RecipeDef = Content.recipes.get(recipe_id)
	if recipe == null or player.dead_until > 0:
		return false
	if status(player.inventory, recipe, player.position) != Status.READY:
		return false
	player.inventory.take(recipe.inputs)
	player.inventory.add(recipe.result, recipe.count)
	return true


## Checked in this order: the station, the inputs, room for the result once they are used.
static func status(inventory: Inventory, recipe: RecipeDef, at: Vector2) -> Status:
	if not at_station(at, recipe.station):
		return Status.AWAY_FROM_STATION
	if not inventory.has_all(recipe.inputs):
		return Status.MISSING_ITEMS
	var after := inventory.copy()
	after.take(recipe.inputs)
	if after.add(recipe.result, recipe.count) > 0:
		return Status.NO_ROOM
	return Status.READY


## Whether a position is close enough to a station to craft there; always for "" (by hand).
static func at_station(at: Vector2, station: StringName) -> bool:
	if station == &"":
		return true
	var stations := Content.tuning.stations
	return (
		stations.has(station) and at.distance_to(stations[station]) <= Content.tuning.station_reach
	)


## The station closest to a position: [id, distance], or [] if there are none.
static func nearest_station(at: Vector2) -> Array:
	var best := []
	var stations := Content.tuning.stations
	for id: StringName in stations:
		var distance := at.distance_to(stations[id])
		if best.is_empty() or distance < best[1]:
			best = [id, distance]
	return best
