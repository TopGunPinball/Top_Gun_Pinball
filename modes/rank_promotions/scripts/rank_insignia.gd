extends MPFVariable
## Rank insignia icon (rank_promotions).
## Reads a rank number from its linked variable:
##   player var rank_level            (promotion overlay)
##   machine var player1_rank..4      (player score boxes, variable_type = machine)
##   -1 = no player -> draws nothing, 0-5 = Ensign..Captain
## Art: res://modes/rank_promotions/images/rank_<n>.png (rank_0.png = Ensign
## ... rank_5.png = Captain), fitted inside this node keeping its aspect.
## Until a file exists, a simple placeholder is drawn:
##   0 gold bar | 1 silver bar | 2 two silver bars | 3 gold oak leaf
##   4 silver oak leaf | 5 silver eagle
## Flares bright when the rank goes up.

const RANK_IMAGE := "res://modes/rank_promotions/images/rank_%d.png"
const GOLD := Color(0.93, 0.74, 0.25, 1)
const SILVER := Color(0.86, 0.88, 0.92, 1)
const EDGE := Color(0.18, 0.14, 0.06, 1)

@export var flare_brightness: float = 1.8
@export var flare_duration: float = 1.2

var rank: int = -1
var _tex: Texture2D = null
var _flare: float = 0.0

func update_text(value) -> void:
	var r := -1
	if value is int or value is float:
		r = int(value)
	elif value is String and value.is_valid_int():
		r = value.to_int()
	if rank >= 0 and r > rank:
		_flare = 1.0
	rank = r
	_tex = null
	if rank >= 0:
		var path := RANK_IMAGE % rank
		if ResourceLoader.exists(path):
			_tex = load(path)
	text = ""
	queue_redraw()

func _process(delta: float) -> void:
	if _flare > 0.0:
		_flare = maxf(0.0, _flare - delta / flare_duration)
		var b := lerpf(1.0, flare_brightness, _flare)
		modulate = Color(b, b, b, 1)

func _draw() -> void:
	if rank < 0:
		return
	if _tex:
		var ts := _tex.get_size()
		var s := minf(size.x / ts.x, size.y / ts.y)
		var d := ts * s
		draw_texture_rect(_tex, Rect2((size - d) / 2.0, d), false)
		return
	match rank:
		0: _bars(1, GOLD)
		1: _bars(1, SILVER)
		2: _bars(2, SILVER)
		3: _leaf(GOLD)
		4: _leaf(SILVER)
		_: _eagle(SILVER)

func _bars(count: int, c: Color) -> void:
	var w := size.x * 0.34 if count == 2 else size.x * 0.7
	var h := size.y * 0.42
	var gap := size.x * 0.08
	var total := w * count + gap * (count - 1)
	var x := (size.x - total) / 2.0
	for i in count:
		var r := Rect2(x + i * (w + gap), (size.y - h) / 2.0, w, h)
		draw_rect(r, c)
		draw_rect(r, EDGE, false, 2.0)

func _leaf(c: Color) -> void:
	var ctr := size / 2.0
	var rx := minf(size.x, size.y * 1.6) * 0.24
	var ry := size.y * 0.40
	var pts := PackedVector2Array()
	for i in 56:
		var a := TAU * i / 56.0
		var wob := 1.0 + 0.16 * sin(a * 7.0)
		pts.append(ctr + Vector2(cos(a) * rx * wob, sin(a) * ry * wob))
	draw_colored_polygon(pts, c)
	draw_polyline(pts + PackedVector2Array([pts[0]]), EDGE, 1.5)
	draw_line(ctr + Vector2(0, -ry * 0.8), ctr + Vector2(0, ry * 1.15), EDGE, 1.5)

func _eagle(c: Color) -> void:
	var s := minf(size.x, size.y * 2.0)
	var ctr := size / 2.0
	var shape := [Vector2(-0.48, -0.05), Vector2(-0.2, -0.25), Vector2(-0.05, -0.08),
		Vector2(0.0, -0.3), Vector2(0.05, -0.08), Vector2(0.2, -0.25), Vector2(0.48, -0.05),
		Vector2(0.1, 0.12), Vector2(0.12, 0.35), Vector2(0.0, 0.25), Vector2(-0.12, 0.35),
		Vector2(-0.1, 0.12)]
	var pts := PackedVector2Array()
	for p in shape:
		pts.append(ctr + p * Vector2(s, s * 0.9))
	draw_colored_polygon(pts, c)
	draw_polyline(pts + PackedVector2Array([pts[0]]), EDGE, 1.5)
