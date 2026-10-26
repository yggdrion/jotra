class_name Crafting
## Turning items into others by a RecipeDef, by hand or at a station (Tuning.stations).


## Crafts a recipe if the player is alive, has the inputs, stands at its station and has room
## for the result. Returns whether it did.
static func craft(player: SimWorld.SimPlayer, recipe_id: StringName) -> bool:
	var recipe: RecipeDef = Content.recipes.get(recipe_id)
	if recipe == null or player.dead_until > 0 or not at_station(player.position, recipe.station):
		return false
	var inventory := player.inventory
	if not inventory.has_all(recipe.inputs):
		return false
	var before := inventory.to_data()
	inventory.take(recipe.inputs)
	if inventory.add(recipe.result, recipe.count) > 0:
		inventory.load_data(before)
		return false
	return true


## Whether a position is close enough to a station to craft there; always for "" (by hand).
static func at_station(at: Vector2, station: StringName) -> bool:
	if station == &"":
		return true
	var stations := Content.tuning.stations
	return (
		stations.has(station) and at.distance_to(stations[station]) <= Content.tuning.station_reach
	)
