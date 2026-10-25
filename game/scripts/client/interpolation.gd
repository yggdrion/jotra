class_name Interpolation
## Positions of remote entities at a past time, blended from buffered snapshots.


## snapshots: [{ms, players: {id: Vector2}}], oldest first. Returns {id: Vector2} at time ms.
## Before the oldest or after the newest snapshot it holds that snapshot (no extrapolation).
## An entity missing from the older snapshot of the pair shows at its newer position.
static func sample(snapshots: Array, ms: int) -> Dictionary:
	if snapshots.is_empty():
		return {}
	var newer: Dictionary = snapshots[-1]
	if ms >= newer.ms:
		return newer.players.duplicate()
	var older: Dictionary = snapshots[0]
	if ms <= older.ms:
		return older.players.duplicate()
	for i in range(1, snapshots.size()):
		if snapshots[i].ms >= ms:
			older = snapshots[i - 1]
			newer = snapshots[i]
			break
	var weight := float(ms - older.ms) / maxf(newer.ms - older.ms, 1)
	var out := {}
	for id: int in newer.players:
		var to: Vector2 = newer.players[id]
		out[id] = older.players.get(id, to).lerp(to, weight)
	return out
