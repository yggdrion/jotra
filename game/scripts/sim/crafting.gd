class_name Crafting
## Turning items into others by a RecipeDef, by hand or at a station piece players built.

## Why a recipe can or can't be crafted right now; the client shows it next to the recipe.
enum Status { READY, AWAY_FROM_STATION, MISSING_ITEMS, NO_ROOM }


## Crafts a recipe if the player is alive and its status is READY, with stations the station
## pieces near it (Building.stations_near). Returns whether it did.
static func craft(player: SimWorld.SimPlayer, recipe_id: StringName, stations := {}) -> bool:
	var recipe: RecipeDef = Content.recipes.get(recipe_id)
	if recipe == null or player.dead_until > 0:
		return false
	if status(player.inventory, recipe, stations) != Status.READY:
		return false
	player.inventory.take(recipe.inputs)
	player.inventory.add(recipe.result, recipe.count)
	return true


## Checked in this order: the station among stations ({piece id: true}), the inputs, room for
## the result once they are used.
static func status(inventory: Inventory, recipe: RecipeDef, stations: Dictionary) -> Status:
	if recipe.station != &"" and not stations.has(recipe.station):
		return Status.AWAY_FROM_STATION
	if not inventory.has_all(recipe.inputs):
		return Status.MISSING_ITEMS
	var after := inventory.copy()
	after.take(recipe.inputs)
	if after.add(recipe.result, recipe.count) > 0:
		return Status.NO_ROOM
	return Status.READY
