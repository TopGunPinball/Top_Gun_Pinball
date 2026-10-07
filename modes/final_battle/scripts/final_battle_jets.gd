extends MPFVariable
## Jets remaining (fb_jets) drawn in the Mach box.
## Uses a jet image if one is found, otherwise the built-in silhouette.
## Lost jets show dimmed up to max_jets. Flashes when a jet is lost.
##
## JET IMAGE: JET_IMAGE_PATH below (top-down jet, nose pointing UP; a
## transparent background looks best). Or drag any image onto "Jet Texture"
## in the Inspector for this node - that wins over the default path.

const JET_IMAGE_PATH := "res://addons/artwork/images/Final Battle/f14_lives.png"

@export var max_jets: int = 4
@export var jet_texture: Texture2D
## Remaining jets: WHITE = the image's own colors. Lost jets: dimmed.
@export var jet_modulate: Color = Color(1, 1, 1, 1)
@export var lost_modulate: Color = Color(0.3, 0.3, 0.3, 0.45)
## Colors for the built-in silhouette (only used when there's no image)
@export var jet_color: Color = Color(0.85, 0.96, 0.96, 1)
@export var lost_color: Color = Color(0.25, 0.3, 0.32, 1)

var jets: int = 3
var _shown_max: int = 3
var _flash := 0.0

func _ready() -> void:
	# MPFVariable._ready() hooks this node up to player variable updates -
	# without this call fb_jets changes never reach update_text()
	super._ready()
	if jet_texture == null and ResourceLoader.exists(JET_IMAGE_PATH):
		jet_texture = load(JET_IMAGE_PATH)
	# Start from the player's current jet count (e.g. 4 with Wingman)
	if not Engine.is_editor_hint() and MPF.game.player is Dictionary:
		var start = MPF.game.player.get(variable_name)
		if start != null:
			jets = int(start)
			_shown_max = clampi(jets, 1, max_jets)
	text = ""
	queue_redraw()

func update_text(value) -> void:
	var v := jets
	if value is int or value is float:
		v = int(value)
	if v < jets:
		_flash = 1.0
	jets = v
	_shown_max = clampi(maxi(_shown_max, v), 1, max_jets)
	text = ""
	queue_redraw()

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		modulate = Color(1, 1, 1, 1).lerp(Color(2, 0.6, 0.4, 1), _flash)
		queue_redraw()

func _draw() -> void:
	var n := _shown_max
	var slot := size.x / float(n)
	var s := minf(slot * 0.8, size.y * 0.9)
	for i in n:
		var ctr := Vector2(slot * (i + 0.5), size.y / 2.0)
		if jet_texture:
			_draw_jet_image(ctr, Vector2(slot * 0.9, size.y * 0.98), i < jets)
		else:
			_draw_jet_shape(ctr, s, i < jets)

# Image, scaled to fit its slot (box w x h), aspect ratio kept
func _draw_jet_image(ctr: Vector2, box: Vector2, alive: bool) -> void:
	var tex_size := jet_texture.get_size()
	var k := minf(box.x / tex_size.x, box.y / tex_size.y)
	var draw_size := tex_size * k
	var rect := Rect2(ctr - draw_size / 2.0, draw_size)
	draw_texture_rect(jet_texture, rect, false, jet_modulate if alive else lost_modulate)

# Built-in silhouette (original drawing)
func _draw_jet_shape(ctr: Vector2, s: float, alive: bool) -> void:
	var pts := PackedVector2Array()
	for p in [Vector2(0, -0.5), Vector2(0.08, -0.15), Vector2(0.48, 0.12), Vector2(0.48, 0.22),
			Vector2(0.08, 0.12), Vector2(0.06, 0.35), Vector2(0.2, 0.48), Vector2(0.2, 0.55),
			Vector2(0, 0.5), Vector2(-0.2, 0.55), Vector2(-0.2, 0.48), Vector2(-0.06, 0.35),
			Vector2(-0.08, 0.12), Vector2(-0.48, 0.22), Vector2(-0.48, 0.12), Vector2(-0.08, -0.15)]:
		pts.append(ctr + p * s)
	if alive:
		draw_colored_polygon(pts, jet_color)
	else:
		draw_polyline(pts + PackedVector2Array([pts[0]]), lost_color, 2.0)
