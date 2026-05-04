extends Sprite2D

## Pulses opacity (modulate.a) between min_alpha and max_alpha while the shot
## is qualified but not yet made. Snaps to solid_alpha when the MPF event
## named in solid_event fires (e.g. "hoi_lo_shot_made").
##
## Pulse phase is synced across all instances by sampling the global system
## clock (Time.get_ticks_msec()). All sprites using this script will pulse in
## phase regardless of when each was added to the scene tree.
##
## Tweak these in the inspector:
##   solid_event: MPF event name that ends the pulse (e.g. "hoi_lo_shot_made")
##   min_alpha: bottom of pulse (default 0.10)
##   max_alpha: top of pulse (default 0.50)
##   solid_alpha: final opacity once shot is made (default 1.0)
##   pulse_duration: time for one full pulse cycle in seconds (default 1.5)

@export var solid_event: String = ""
@export var min_alpha: float = 0.10
@export var max_alpha: float = 0.50
@export var solid_alpha: float = 1.0
@export var pulse_duration: float = 1.5

## Set true to print every signal/method on MPF.server when the scene loads.
const DEBUG_LOG_EVENTS: bool = true

var _is_solid: bool = false
var _solid_tween: Tween = null
var _connected_via: String = ""

func _ready() -> void:
	# Set initial alpha to the synced phase value (so first frame isn't off)
	modulate.a = _compute_synced_alpha()

	if solid_event == "":
		push_warning("[pulse_to_solid] solid_event not set — pulse will run forever.")
		return

	if not _try_connect():
		push_error("[pulse_to_solid] Could not subscribe to MPF event '%s'. Check Godot console for available signals/methods." % solid_event)
		if DEBUG_LOG_EVENTS:
			_dump_server_introspection()

func _process(_delta: float) -> void:
	# Once the shot is made, _is_solid is true and we let the solid tween (or
	# its final state) own the alpha — don't overwrite.
	if _is_solid:
		return
	modulate.a = _compute_synced_alpha()

## Compute the pulse alpha at the current global time. Same formula across all
## instances → all sprites sit at the same phase.
func _compute_synced_alpha() -> float:
	# Smooth sine wave between min_alpha and max_alpha.
	# t cycles 0.0 .. 1.0 over pulse_duration seconds.
	var ms: int = Time.get_ticks_msec()
	var t: float = fmod(float(ms) / 1000.0, pulse_duration) / pulse_duration
	# 0.5 + 0.5*sin gives 0..1 range; map to min..max
	var wave: float = 0.5 - 0.5 * cos(t * TAU)
	return lerp(min_alpha, max_alpha, wave)

func _try_connect() -> bool:
	if get_node_or_null("/root/MPF") == null:
		push_error("[pulse_to_solid] MPF singleton not found at /root/MPF")
		return false

	var server = MPF.server
	if server == null:
		push_error("[pulse_to_solid] MPF.server is null")
		return false

	# Strategy 1: server has a signal named after the event itself
	if server.has_signal(solid_event):
		server.connect(solid_event, _on_solid_event)
		_connected_via = "direct signal '%s'" % solid_event
		print("[pulse_to_solid] Connected via direct signal: %s" % solid_event)
		return true

	# Strategy 2: GMC dispatches all events through a single signal
	var dispatcher_candidates = ["event_received", "mpf_event", "received_event", "event", "incoming_event", "event_dispatched"]
	for sig in dispatcher_candidates:
		if server.has_signal(sig):
			server.connect(sig, _on_dispatched_event)
			_connected_via = "dispatcher signal '%s'" % sig
			print("[pulse_to_solid] Connected via dispatcher signal: %s" % sig)
			return true

	# Strategy 3: register a per-event handler via method
	var registration_methods = ["add_event_handler", "add_event_listener", "register_event_handler", "on_event", "listen_for_event"]
	for m in registration_methods:
		if MPF.has_method(m):
			MPF.call(m, solid_event, Callable(self, "_on_solid_event"))
			_connected_via = "MPF.%s" % m
			print("[pulse_to_solid] Connected via MPF.%s" % m)
			return true
		if server.has_method(m):
			server.call(m, solid_event, Callable(self, "_on_solid_event"))
			_connected_via = "MPF.server.%s" % m
			print("[pulse_to_solid] Connected via MPF.server.%s" % m)
			return true

	return false

func _dump_server_introspection() -> void:
	var server = MPF.server if get_node_or_null("/root/MPF") != null else null
	if server == null:
		return
	print("[pulse_to_solid] === MPF.server signals ===")
	for s in server.get_signal_list():
		print("  signal: %s" % s.name)
	print("[pulse_to_solid] === MPF.server event-related methods ===")
	for m in server.get_method_list():
		var n = m.name as String
		var lower = n.to_lower()
		if "event" in lower or "handler" in lower or "listener" in lower or "register" in lower or "on_" in lower:
			print("  method: %s" % n)
	print("[pulse_to_solid] === MPF singleton methods (filtered) ===")
	for m in MPF.get_method_list():
		var n = m.name as String
		var lower = n.to_lower()
		if "event" in lower or "handler" in lower or "listener" in lower:
			print("  MPF.%s" % n)

func _on_solid_event(_arg = null) -> void:
	print("[pulse_to_solid] solid_event '%s' received → going solid" % solid_event)
	_go_solid()

## Dispatcher handler — receives ALL events through a generic signal.
func _on_dispatched_event(event_name = null, _kwargs = null) -> void:
	if typeof(event_name) == TYPE_STRING and event_name == solid_event:
		print("[pulse_to_solid] dispatcher matched '%s' → going solid" % solid_event)
		_go_solid()

func _go_solid() -> void:
	if _is_solid:
		return
	_is_solid = true
	# _process now stops driving alpha; smoothly tween from current value to solid.
	if _solid_tween and _solid_tween.is_valid():
		_solid_tween.kill()
	_solid_tween = create_tween()
	_solid_tween.tween_property(self, "modulate:a", solid_alpha, 0.25)
