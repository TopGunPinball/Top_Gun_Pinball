extends MPFVariable
## MPFVariable with HUD effects for the Pilot Jackpot readout.
##
##   count_up : when the value goes UP, count from the number currently shown
##              to the new one (ease-out) instead of jumping. The first value
##              on screen counts up from 0.
##   pop      : when the value goes up, the label briefly grows and flashes
##              toward white, then settles back.
##
## Emits value_increased(new_value) whenever the value goes up - the readout
## (pilot_hud_readout.gd) listens for this to flare.

signal value_increased(new_value)

@export var count_up: bool = false
@export var count_duration: float = 1.0
@export var pop: bool = false
@export var pop_scale: float = 1.45
@export var pop_duration: float = 0.45
@export var pop_flash_color: Color = Color(1, 1, 1, 1)

var _shown: float = 0.0
var _last = null
var _base_color: Color
var _count_tween: Tween
var _pop_tween: Tween

func _ready() -> void:
	_base_color = get_theme_color("font_color")
	super._ready()

func update_text(value) -> void:
	if not (value is int or value is float):
		super.update_text(value)
		return
	var increased: bool = _last == null or value > _last
	_last = value
	if increased and value > 0:
		value_increased.emit(value)
		if pop:
			_do_pop()
	if count_up and increased and is_inside_tree():
		if _count_tween:
			_count_tween.kill()
		_count_tween = create_tween()
		_count_tween.tween_method(_show_number, _shown, float(value), count_duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_shown = float(value)
		super.update_text(value)

func _show_number(v: float) -> void:
	_shown = v
	super.update_text(int(round(v)))

func _do_pop() -> void:
	if not is_inside_tree():
		return
	# Grow from the left edge for left-aligned text, from the center otherwise
	var px: float = 0.0 if horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else size.x / 2.0
	pivot_offset = Vector2(px, size.y / 2.0)
	if _pop_tween:
		_pop_tween.kill()
	scale = Vector2(pop_scale, pop_scale)
	add_theme_color_override("font_color", pop_flash_color)
	_pop_tween = create_tween().set_parallel(true)
	_pop_tween.tween_property(self, "scale", Vector2.ONE, pop_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, "theme_override_colors/font_color", _base_color, pop_duration)
