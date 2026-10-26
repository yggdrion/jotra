class_name PieceView
extends Node2D
## Placeholder for a built piece standing on its tile's center: shapes in the piece's color,
## a health bar once damaged, a glow for a fire's light at night. Also the build mode's ghost.

const OUTLINE := Color(1, 1, 1, 0.8)
const HALF := WorldGen.TILE / 2.0

var piece: Building.Piece:
	set(value):
		piece = value
		_update_light()
		queue_redraw()
## Outlined: the door or chest E acts on.
var highlighted := false:
	set(value):
		if value != highlighted:
			highlighted = value
			queue_redraw()
## Drawn see-through in this color instead, for the build ghost.
var ghost := Color.TRANSPARENT:
	set(value):
		ghost = value
		queue_redraw()
var _light: PointLight2D


func _update_light() -> void:
	var radius := piece.def().light if piece else 0.0
	if radius <= 0 or ghost.a > 0:
		if _light:
			_light.queue_free()
			_light = null
		return
	if _light == null:
		var gradient := Gradient.new()
		gradient.colors = [Color(1, 0.8, 0.5, 1), Color(1, 0.6, 0.3, 0)]
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1, 0.5)
		texture.width = 128
		texture.height = 128
		_light = PointLight2D.new()
		_light.texture = texture
		_light.position = Vector2(0, -4)
		add_child(_light)
	_light.texture_scale = radius * 2 / 128.0


func _draw() -> void:
	if piece == null:
		return
	var def := piece.def()
	var color := def.color if ghost.a == 0 else ghost
	var tile := Rect2(-HALF, -HALF, WorldGen.TILE, WorldGen.TILE)
	if highlighted:
		draw_rect(tile.grow(1), OUTLINE, false, 1)
	if def.flat:
		draw_rect(tile, color)
		for y in [-HALF + 5, -HALF + 10]:
			draw_line(Vector2(-HALF, y), Vector2(HALF, y), color.darkened(0.3))
	elif def.door:
		if piece.open:
			draw_rect(Rect2(-HALF, -HALF - 12, 3, WorldGen.TILE + 12), color)
		else:
			draw_rect(Rect2(-HALF, -HALF - 12, WorldGen.TILE, WorldGen.TILE + 12), color)
			draw_circle(Vector2(4, -4), 1.5, Color("feae34"))
	elif def.blocks and not def.station and def.storage == 0:
		# A wall: a block standing taller than its tile.
		draw_rect(Rect2(-HALF, -HALF - 12, WorldGen.TILE, WorldGen.TILE + 12), color)
		draw_rect(Rect2(-HALF, -HALF - 12, WorldGen.TILE, 3), color.lightened(0.2))
	elif def.station:
		draw_rect(Rect2(-8, -8, 16, 6), color)
		draw_rect(Rect2(-7, -2, 2, 6), color.darkened(0.4))
		draw_rect(Rect2(5, -2, 2, 6), color.darkened(0.4))
		draw_rect(Rect2(-4, -11, 5, 3), Color("8b9bb4"))
	elif def.storage > 0:
		draw_rect(Rect2(-7, -8, 14, 12), color)
		draw_rect(Rect2(-7, -4, 14, 2), Color("feae34"))
		draw_rect(Rect2(-1, -6, 2, 3), Color("feae34"))
	else:
		# A fire: stones and a flame.
		draw_circle(Vector2(0, 2), 6, Color("5a6988"))
		draw_colored_polygon(
			PackedVector2Array([Vector2(-4, 2), Vector2(0, -10), Vector2(4, 2)]), color
		)
		draw_colored_polygon(
			PackedVector2Array([Vector2(-2, 2), Vector2(0, -5), Vector2(2, 2)]), Color("feae34")
		)
	if ghost.a == 0 and piece.health < def.health:
		var share := piece.health / def.health
		draw_rect(Rect2(-HALF, HALF + 1, WorldGen.TILE, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-HALF, HALF + 1, WorldGen.TILE * share, 2), Color("e43b44"))
