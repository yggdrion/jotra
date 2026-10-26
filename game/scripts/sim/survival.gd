class_name Survival
## Survival rules shared by server and client (PLAN §5.4): the day/night clock, read off the
## world's time, and what night does to spawns. Hunger itself is ticked in SimWorld. The
## numbers are data: Content.tuning and the food items.


## Seconds into the current day, night included.
static func time_of_day(time: float) -> float:
	var t := Content.tuning
	return fposmod(time, t.day_length + t.night_length)


## 1, 2, … counting from the world's first dawn.
static func day_number(time: float) -> int:
	var t := Content.tuning
	return floori(time / (t.day_length + t.night_length)) + 1


static func is_night(time: float) -> bool:
	return time_of_day(time) >= Content.tuning.day_length


## How light it is, 0 (night) to 1 (day), fading over twilight at dusk and dawn.
static func daylight(time: float) -> float:
	var t := Content.tuning
	var at := time_of_day(time)
	var since_dusk := at - (t.day_length - t.twilight)
	if since_dusk < 0:
		# Dawn: the light comes back over the first twilight seconds of the day.
		return clampf(at / t.twilight, 0.0, 1.0) if time >= t.twilight else 1.0
	if at < t.day_length:
		return 1.0 - since_dusk / t.twilight
	return 0.0


## Seconds until the next dusk or dawn.
static func until_change(time: float) -> float:
	var t := Content.tuning
	var at := time_of_day(time)
	return t.day_length - at if at < t.day_length else t.day_length + t.night_length - at


## Multipliers on enemy count, health, damage and speed for spawns at this time: 1 by day.
static func night_scale(time: float) -> Dictionary:
	var t := Content.tuning
	if not is_night(time):
		return {count = 1.0, health = 1.0, damage = 1.0, speed = 1.0}
	return {
		count = t.night_count,
		health = t.night_health,
		damage = t.night_damage,
		speed = t.night_speed,
	}
