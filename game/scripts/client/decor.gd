class_name Decor
extends RefCounted
## Scenery the client scatters from the seed: bones, plants, stumps, graves, the odd glowing
## totem. The sim knows nothing of it; it never blocks and is hidden under built pieces.
## Also loads the props' sprites, animating the strips in ANIMATED.

## Per biome (meadow, forest, marsh, bone hills), about one tile in this many without a prop
## gets a piece: sparse where the trees already crowd.
const EVERY: Array[int] = [26, 40, 22, 18]
## Per biome, the pieces picked from (repeats weigh more), none shared: the meadow is dry grass
## and old graves, the forest deadwood, the marsh green growth and grasping hands, the bone hills
## bones, ruins and glowing totems.
const BIOME := [
	["dry_tuft", "dry_tuft", "dry_sprig", "dry_sprig", "dry_bush", "grave_a", "grave_e"],
	["stump", "stump_cut", "stump_broken", "log", "thorns", "thorns_wide", "thorn_sprig"],
	["leaves_big", "leaves", "leaves", "sprout", "sprout", "dead_arm", "dead_hand"],
	[
		"bones_small",
		"skull",
		"skulls",
		"ribs",
		"bone_arm",
		"antler",
		"spine",
		"beak_skull",
		"bone",
		"long_bone",
		"horn",
		"bone_heap",
		"grave_b",
		"grave_c",
		"rubble",
		"ruin",
		"skull_pile",
		"totem",
		"skull_altar",
	],
]
## Lie flat with the ground; the rest stand y-sorted with the players.
const FLAT: PackedStringArray = [
	"bones_small",
	"skull",
	"skulls",
	"bone_arm",
	"antler",
	"spine",
	"bone",
	"long_bone",
	"horn",
	"leaves",
	"sprout",
	"dry_tuft",
	"dry_sprig",
	"thorn_sprig",
	"thorns_wide",
	"rubble",
]
## Six-frame strips, played at FPS.
const ANIMATED: PackedStringArray = [
	"decor/totem", "decor/skull_altar", "tree_drip", "tree_drip_small", "shrine"
]
const FPS := 8.0
const DIR := "res://assets/craftpix/props/%s.png"

static var _cache := {}


## A prop sprite by its path under props/, animated if it is a strip.
static func sprite(path: String) -> Texture2D:
	if not _cache.has(path):
		var texture: Texture2D = load(DIR % path)
		if path in ANIMATED:
			texture = _animate(texture)
		_cache[path] = texture
	return _cache[path]


## The piece for a tile, "" for none; roll is any hash of the tile.
static func pick(biome: int, roll: int) -> String:
	var every := EVERY[biome]
	if roll % every != 0:
		return ""
	var pieces: Array = BIOME[biome]
	return pieces[(roll / every) % pieces.size()]


static func _animate(strip: Texture2D) -> AnimatedTexture:
	var animated := AnimatedTexture.new()
	animated.frames = 6
	animated.speed_scale = FPS
	# Frames cut out on their own: an AtlasTexture frame would draw the whole strip.
	var image := strip.get_image()
	var width := strip.get_width() / 6
	for i in 6:
		var region := Rect2i(i * width, 0, width, strip.get_height())
		animated.set_frame_texture(i, ImageTexture.create_from_image(image.get_region(region)))
		animated.set_frame_duration(i, 1.0)
	return animated


## One piece of scenery, its base on its position, mirrored or not.
class View:
	extends Node2D

	## How far below the sprite's bottom edge its base stands (the shadow reaches past it), px.
	const BASE := 3

	var texture: Texture2D
	var flip := false

	func _draw() -> void:
		var size := texture.get_size()
		if flip:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
		draw_texture(texture, Vector2(-size.x / 2, -size.y + BASE))
