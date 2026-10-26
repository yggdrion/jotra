class_name Interpolation
## Positions of remote entities at a past time, blended from buffered snapshots.


## snapshots: [{ms, <key>: {id: value}}], oldest first, values Vector2 or Vector3. Returns
## {id: value} of that key at time ms. Before the oldest or after the newest snapshot it holds
## that snapshot (no extrapolation). An entity missing from the older snapshot of the pair
## shows at its newer value.
static func sample(snapshots: Array, ms: int, key := "players") -> Dictionary:
	if snapshots.is_empty():
		return {}
	var newer: Dictionary = snapshots[-1]
	if ms >= newer.ms:
		return newer[key].duplicate()
	var older: Dictionary = snapshots[0]
	if ms <= older.ms:
		return older[key].duplicate()
	for i in range(1, snapshots.size()):
		if snapshots[i].ms >= ms:
			older = snapshots[i - 1]
			newer = snapshots[i]
			break
	var weight := float(ms - older.ms) / maxf(newer.ms - older.ms, 1)
	var out := {}
	for id: int in newer[key]:
		var to: Variant = newer[key][id]
		out[id] = older[key].get(id, to).lerp(to, weight)
	return out
