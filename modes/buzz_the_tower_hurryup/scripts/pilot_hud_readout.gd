extends Control
## HUD readout: slowly pulses this node and everything inside it between dim
## and full brightness (phosphor "breathing"), and flares brighter when the
## linked HUD variable's value goes up. Also flares when the slide appears.
##
## Optional URGENCY (used by Buzz the Tower): point urgency_source at a
## pilot_hud_gauge. While the gauge is full the pulse is normal; as it drains
## the pulse speeds up toward fast_period, and below blink_below it switches
## to a hard on/off blink. Leave urgency_source empty for a plain pulse
## (Pilot Jackpot).

@export var period: float = 1.4             ## seconds per pulse (gauge full / no gauge)
@export var dim: float = 0.62               ## brightness at the bottom of the pulse
@export var flare_brightness: float = 1.35  ## brightness at the peak of a flare
@export var flare_duration: float = 1.0     ## seconds for a flare to fade out
@export var flare_source: NodePath          ## node with a value_increased signal

@export_group("Urgency")
@export var urgency_source: NodePath        ## a pilot_hud_gauge (has .pct 0-1)
@export var fast_period: float = 0.3        ## pulse period when the gauge is nearly empty
@export var blink_below: float = 0.2        ## gauge fraction where the hard blink starts
@export var blink_rate: float = 4.0         ## blinks per second
@export var blink_on: float = 1.15          ## brightness of a blink "on"
@export var blink_off: float = 0.35         ## brightness of a blink "off"

var _phase: float = 0.0
var _t: float = 0.0
var _flare: float = 1.0   # start with a flare as the slide appears
var _gauge: Node = null

func _ready() -> void:
	if flare_source:
		var n = get_node_or_null(flare_source)
		if n and n.has_signal("value_increased"):
			n.value_increased.connect(_on_value_increased)
	if urgency_source:
		_gauge = get_node_or_null(urgency_source)

func _on_value_increased(_v) -> void:
	_flare = 1.0

func _process(delta: float) -> void:
	_t += delta
	var pct: float = 1.0
	if _gauge and "pct" in _gauge:
		pct = _gauge.pct
	var b: float
	if _gauge and pct < blink_below:
		b = blink_on if int(_t * blink_rate * 2.0) % 2 == 0 else blink_off
	else:
		var p: float = lerpf(fast_period, period, pct) if _gauge else period
		_phase += delta / maxf(p, 0.05)
		b = dim + (1.0 - dim) * (0.5 + 0.5 * sin(TAU * _phase))
	_flare = maxf(0.0, _flare - delta / flare_duration)
	b = lerpf(b, flare_brightness, _flare)
	modulate = Color(b, b, b, 1.0)
