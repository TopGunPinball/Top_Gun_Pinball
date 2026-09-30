extends MPFVariable
## Segmented gauge (fuel-gauge style) driven by a 0-100 player variable.
## Extends MPFVariable so it gets player variable updates the same way the
## labels do, but draws segments instead of text.
##
##   variable_name : player variable holding 0-100 (e.g. buzz_tower_pct)
##   segments      : number of segments across the gauge
##   lit_color     : color of lit segments
##   unlit_color   : color of unlit segments
##   gap           : pixels between segments
##
## pct (0.0-1.0) is readable by other nodes (pilot_hud_readout uses it to
## speed up its pulse as the gauge drains).

@export var segments: int = 24
@export var lit_color: Color = Color(1.0, 0.69, 0.0, 1)
@export var unlit_color: Color = Color(0.22, 0.15, 0.0, 1)
@export var gap: float = 4.0

var pct: float = 1.0

func update_text(value) -> void:
	if value is int or value is float:
		pct = clampf(float(value) / 100.0, 0.0, 1.0)
	text = ""
	queue_redraw()

func _draw() -> void:
	if segments <= 0:
		return
	var w: float = size.x / segments
	var lit: int = int(ceil(pct * segments - 0.0001))
	for i in segments:
		var r := Rect2(i * w + gap / 2.0, 0.0, w - gap, size.y)
		draw_rect(r, lit_color if i < lit else unlit_color)
