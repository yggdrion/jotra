class_name PieceView
extends Node2D
## A built piece on its tile's center: its sprite, brighter while E acts on it, a health bar
## once damaged, a glow for a fire's light at night. Also the build mode's ghost.

const HIGHLIGHT := Color(1.6, 1.6, 1.6)
const HALF := WorldGen.TILE / 2.0

var piece: Building.Piece:
	set(value):
		piece = value
		_update_light()
		queue_redraw()
## Brighter: the door or chest E acts on.
var highlighted := false:
	set(value):
		if value != highlighted:
			highlighted = value
			queue_redraw()
## Drawn tinted see-through in this color instead, for the build ghost.
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
	var tint := ghost if ghost.a > 0 else (HIGHLIGHT if highlighted else Color.WHITE)
	var icon := def.open_icon if def.door and piece.open else def.icon
	var size := icon.get_size()
	# Standing on the tile's bottom edge, so tall pieces rise above their tile.
	draw_texture(icon, Vector2(-size.x / 2, HALF - size.y), tint)
	if ghost.a == 0 and piece.health < def.health:
		var share := piece.health / def.health
		draw_rect(Rect2(-HALF, HALF + 1, WorldGen.TILE, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-HALF, HALF + 1, WorldGen.TILE * share, 2), Color("e43b44"))
