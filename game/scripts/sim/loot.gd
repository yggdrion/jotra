class_name Loot
## Drop tables: an Array of {item: id, chance: 0..1, min: count, max: count}, each entry rolled
## on its own, so a table can give several items or none. Rarer items get lower chances.


## [[item id, count], ...] of what one roll of table gives.
static func roll(table: Array, rng: RandomNumberGenerator) -> Array[Array]:
	var out: Array[Array] = []
	for entry: Dictionary in table:
		if rng.randf() < float(entry.get("chance", 1.0)):
			var count := rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
			if count > 0:
				out.append([StringName(entry.item), count])
	return out
