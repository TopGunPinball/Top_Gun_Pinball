extends "res://modes/buzz_the_tower_hurryup/scripts/pilot_hud_gauge.gd"
## Merit bar (rank_promotions). Same segmented gauge as Buzz the Tower,
## driven by player var rank_merit_pct (0-100 progress within the current
## rank). Flares bright whenever it changes (merit gained, or the reset to
## the new rank's range after a promotion).

@export var flare_brightness: float = 1.6
@export var flare_duration: float = 1.0

var _seen := false
var _f := 0.0

func update_text(value) -> void:
	var before := pct
	super.update_text(value)
	if _seen and not is_equal_approx(before, pct):
		_f = 1.0
	_seen = true

func _process(delta: float) -> void:
	if _f > 0.0:
		_f = maxf(0.0, _f - delta / flare_duration)
		var b := lerpf(1.0, flare_brightness, _f)
		modulate = Color(b, b, b, 1)
