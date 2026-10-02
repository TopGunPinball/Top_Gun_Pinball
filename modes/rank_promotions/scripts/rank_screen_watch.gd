extends Node
## Screen watcher (rank_promotions).
## Lets rank promotions wait for a clear moment instead of talking over or
## covering other content. Checks a few times a second for:
##   - an event video playing: any visible, playing VideoStreamPlayer that is
##     NOT set to loop (looping backgrounds don't count) and isn't inside one
##     of the ignore_slides
##   - a voice callout playing: any playing AudioStreamPlayer on voice_bus
##     (only when check_voice is on)
##
## Two uses:
##   send_to_mpf = true  (rank_panel): posts rank_screen_busy /
##       rank_screen_clear to MPF whenever the state changes, plus a heartbeat
##       every few seconds so MPF never keeps a stale state.
##   hide_target set     (rank_promotion): hides that node if a video starts
##       while the promotion overlay is up, so the video is never covered.
##       (check_voice off there - the overlay's own callout is playing.)

@export var send_to_mpf: bool = false
@export var check_voice: bool = true
@export var voice_bus: String = "voice"
@export var hide_target: NodePath
@export var ignore_slides: Array[String] = ["base_slide", "rank_panel", "rank_promotion"]
@export var check_interval: float = 0.25
@export var heartbeat: float = 5.0

var _busy := false
var _sent_once := false
var _t := 0.0
var _hb := 0.0

func _process(delta: float) -> void:
	_t += delta
	_hb += delta
	if _t < check_interval:
		return
	_t = 0.0
	var b := _is_busy()
	if send_to_mpf and (b != _busy or not _sent_once or _hb >= heartbeat):
		_send("rank_screen_busy" if b else "rank_screen_clear")
		_sent_once = true
		_hb = 0.0
	_busy = b
	if b and hide_target:
		var n = get_node_or_null(hide_target)
		if n is CanvasItem:
			n.visible = false

func _is_busy() -> bool:
	var root := get_tree().root
	for n in root.find_children("*", "VideoStreamPlayer", true, false):
		var v := n as VideoStreamPlayer
		if v and v.is_playing() and v.is_visible_in_tree() and v.get("loop") != true and not _ignored(v):
			return true
	if check_voice:
		for n in root.find_children("*", "AudioStreamPlayer", true, false):
			var a := n as AudioStreamPlayer
			if a and a.playing and String(a.bus) == voice_bus:
				return true
	return false

func _ignored(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if String(p.name) in ignore_slides:
			return true
		p = p.get_parent()
	return false

func _send(e: String) -> void:
	if MPF and MPF.server:
		MPF.server.send_event(e)
