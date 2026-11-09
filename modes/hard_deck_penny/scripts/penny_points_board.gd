extends Control
## MAVERICK & PENNY - 7-slot points countdown board.
##
## Shows the value each counting shot is worth RIGHT NOW (its countdown value x
## the player's total_scoring_multiplier), with the shot's name under it.
## Everything comes from player variables set by
## hard_deck_penny.yaml - no MPF events needed:
##   penny_<key>_state   0 = lit, 1 = counting down, 2 = collected
##   penny_<key>_value   raw countdown value (1,500,000 -> 500,000 floor)
##   penny_<key>_order   start sequence (1, 2, 3 ...)
##   total_scoring_multiplier
##
## SLOT RULES
##   - A shot gets a slot when it starts counting (in the order they start).
##     It keeps that slot until it is collected, then the slot frees up.
##   - All 7 slots full and a NEW shot starts: it replaces the slot showing
##     the LOWEST value (that shot keeps counting, just isn't shown).
##   - When a slot frees up, the highest-value hidden shot moves into it.
##
## LAYOUT: the slots are the child nodes slot1 .. slot7 of this node, each with
##   two Labels: "points" and "shot". Move / resize / restyle them in the editor
##   freely - the script only sets their text, visibility and blink.

const SHOT_KEYS := ["ll", "lo", "lr", "sp", "cnt", "twr", "tl", "tr", "rr",
	"i", "c", "e", "m", "a", "n"]
const SHOT_NAMES := {
	"ll": "LEFT LANE", "lo": "LEFT ORBIT", "lr": "LEFT RAMP", "sp": "SPINNER",
	"cnt": "CENTER TARGET", "twr": "TOWER", "tl": "TOP LOOP", "tr": "TOP RAMP",
	"rr": "RIGHT RAMP", "i": "ICEMAN - I", "c": "ICEMAN - C", "e": "ICEMAN - E",
	"m": "ICEMAN - M", "a": "ICEMAN - A", "n": "ICEMAN - N",
}
const FLOOR_VALUE := 500000
const SLOT_COUNT := 7

## Blink speeds for the points label (matches the insert: fast while counting,
## slow at the floor). 0 = no blink.
@export var blink_fast_seconds: float = 0.3
@export var blink_slow_seconds: float = 1.2
## Points label color while counting / at the floor
@export var counting_color: Color = Color(1.0, 0.75, 0.9, 1.0)
@export var floor_color: Color = Color(0.72, 0.5, 0.86, 1.0)

var _slots: Array = []        # shot key per slot ("" = empty)
var _seen := {}               # shots already placed once (only NEW shots may bump a slot)
var _slot_nodes: Array = []
var _blink_t := 0.0


func _ready() -> void:
	for i in SLOT_COUNT:
		_slots.append("")
		_slot_nodes.append(get_node_or_null("slot%d" % (i + 1)))
	if Engine.is_editor_hint():
		return
	MPF.game.player_update.connect(_on_player_update)
	# Pick up shots already counting (slide created mid-mode)
	var started: Array = []
	for k in SHOT_KEYS:
		if _state(k) == 1:
			started.append(k)
	started.sort_custom(func(a, b): return _order(a) < _order(b))
	for k in started:
		_place_new(k)
	_refresh()


func _exit_tree() -> void:
	if MPF and MPF.game and MPF.game.player_update.is_connected(_on_player_update):
		MPF.game.player_update.disconnect(_on_player_update)


func _on_player_update(var_key: String, _value) -> void:
	if not (var_key.begins_with("penny_") or var_key == "total_scoring_multiplier"):
		return
	_update_slots()
	_refresh()


func _update_slots() -> void:
	# 1. Free the slots of shots that are no longer counting (collected / reset)
	for i in SLOT_COUNT:
		var k: String = _slots[i]
		if k != "" and _state(k) != 1:
			_slots[i] = ""
	for k in _seen.keys():
		if _state(k) != 1:
			_seen.erase(k)
	# 2. Newly started shots, in the order they started
	var fresh: Array = []
	for k in SHOT_KEYS:
		if _state(k) == 1 and not _seen.has(k):
			fresh.append(k)
	fresh.sort_custom(func(a, b): return _order(a) < _order(b))
	for k in fresh:
		_place_new(k)
	# 3. Fill any empty slot with the highest-value hidden shot
	for i in SLOT_COUNT:
		if _slots[i] != "":
			continue
		var best := ""
		for k in _seen.keys():
			if k in _slots:
				continue
			if best == "" or _value(k) > _value(best):
				best = k
		if best != "":
			_slots[i] = best


func _place_new(k: String) -> void:
	_seen[k] = true
	if k in _slots:
		return
	var empty := _slots.find("")
	if empty != -1:
		_slots[empty] = k
		return
	# Full: replace the slot showing the lowest value
	var low := 0
	for i in range(1, SLOT_COUNT):
		if _value(_slots[i]) < _value(_slots[low]):
			low = i
	_slots[low] = k


func _refresh() -> void:
	var mult := _mult()
	for i in SLOT_COUNT:
		var node: Control = _slot_nodes[i]
		if node == null:
			continue
		var k: String = _slots[i]
		node.visible = k != ""
		if k == "":
			continue
		var pts: Label = node.get_node_or_null("points")
		var shot: Label = node.get_node_or_null("shot")
		var v := _value(k)
		if pts:
			pts.text = _commas(int(round(v * mult)))
			pts.add_theme_color_override("font_color",
				floor_color if v <= FLOOR_VALUE else counting_color)
		if shot:
			shot.text = SHOT_NAMES.get(k, k.to_upper())


func _process(delta: float) -> void:
	_blink_t += delta
	for i in SLOT_COUNT:
		var node: Control = _slot_nodes[i]
		if node == null or _slots[i] == "":
			continue
		var pts: Label = node.get_node_or_null("points")
		if pts == null:
			continue
		var period := blink_slow_seconds if _value(_slots[i]) <= FLOOR_VALUE else blink_fast_seconds
		if period <= 0.0:
			pts.modulate.a = 1.0
		else:
			pts.modulate.a = 1.0 if fmod(_blink_t, period) < period * 0.6 else 0.35


# ---- player variable helpers ------------------------------------------------
func _pv(name: String, fallback = 0):
	if MPF.game and MPF.game.player:
		return MPF.game.player.get(name, fallback)
	return fallback

func _state(k: String) -> int:
	return int(_pv("penny_%s_state" % k, 0))

func _value(k: String) -> int:
	return int(_pv("penny_%s_value" % k, 0))

func _order(k: String) -> int:
	return int(_pv("penny_%s_order" % k, 0))

func _mult() -> float:
	return float(_pv("total_scoring_multiplier", 1.0))

func _commas(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
