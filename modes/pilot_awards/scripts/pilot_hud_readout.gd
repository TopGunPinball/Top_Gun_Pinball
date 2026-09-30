extends Control
## Pilot Jackpot readout: slowly pulses this node and everything inside it
## between dim and full brightness (green phosphor "breathing"), and flares
## brighter when the linked HUD variable's value goes up. Also flares when the
## slide first appears.

@export var period: float = 1.4             ## seconds per pulse
@export var dim: float = 0.62               ## brightness at the bottom of the pulse
@export var flare_brightness: float = 1.35  ## brightness at the peak of a flare
@export var flare_duration: float = 1.0     ## seconds for a flare to fade out
@export var flare_source: NodePath          ## node with a value_increased signal

var _t: float = 0.0
var _flare: float = 1.0   # start with a flare as the slide appears

func _ready() -> void:
	if flare_source:
		var n = get_node_or_null(flare_source)
		if n and n.has_signal("value_increased"):
			n.value_increased.connect(_on_value_increased)

func _on_value_increased(_v) -> void:
	_flare = 1.0

func _process(delta: float) -> void:
	_t += delta
	var p: float = dim + (1.0 - dim) * (0.5 + 0.5 * sin(TAU * _t / period))
	_flare = maxf(0.0, _flare - delta / flare_duration)
	var b: float = lerpf(p, flare_brightness, _flare)
	modulate = Color(b, b, b, 1.0)
