extends Control
## FINAL BATTLE video player (one for the whole mode).
##
## MPF -> Godot:  fb_video (video, urgent)   fb_video_clear
## Godot -> MPF:  fb_video_started (video)   when a video starts playing
##                fb_video_done (video)      when a video finishes, is
##                                          interrupted, or its placeholder ends
##
## Videos load from res://addons/artwork/videos/final_battle/<name>.ogv
## Queue rules:
##   - a normal (step) video waits if one is playing; only ONE waits - a newer
##     one replaces it, so a burst of shots never builds a backlog
##   - an urgent video (urgent = 1) clears the queue and plays immediately
##   - a missing file shows a placeholder card with the name for
##     placeholder_seconds, then counts as finished (so the game never stalls)

const VIDEO_PATH := "res://addons/artwork/videos/final_battle/%s.ogv"

@export var placeholder_seconds: float = 2.5
## DUCKING
## Music is lowered while a video plays (GMC ducking, 0 = none, 1 = mute)
@export var music_duck_under_video: float = 0.6
## Video sound is lowered while a voice callout plays (dB)
@export var video_duck_db: float = -18.0
@export var voice_bus: String = "voice"

@onready var _player: VideoStreamPlayer = $video
@onready var _card: Control = $placeholder
@onready var _card_label: Label = $placeholder/label

var _current := ""
var _pending := ""
var _card_time := 0.0
var _voice_check := 0.0
var _voice_active := false
## The music duck this player added for the current video (released when the
## video ends, is skipped or is replaced)
var _video_duck: DuckSettings = null

func _ready() -> void:
	_player.finished.connect(_on_finished)
	_card.visible = false
	MPF.server.add_event_handler("fb_video", _on_fb_video)
	MPF.server.add_event_handler("fb_video_clear", _on_fb_video_clear)

func _exit_tree() -> void:
	MPF.server.remove_event_handler("fb_video", _on_fb_video)
	MPF.server.remove_event_handler("fb_video_clear", _on_fb_video_clear)

func _on_fb_video(kwargs: Dictionary) -> void:
	var vname := str(kwargs.get("video", ""))
	if vname == "":
		return
	var urgent := int(kwargs.get("urgent", 0)) == 1
	if urgent:
		_pending = ""
		_interrupt_current()
		_play(vname)
	elif _current != "":
		_pending = vname
	else:
		_play(vname)

func _on_fb_video_clear(_kwargs: Dictionary) -> void:
	_pending = ""
	_interrupt_current()

func _interrupt_current() -> void:
	if _current == "":
		return
	var was := _current
	_release_video_duck()
	_player.stop()
	# Hide it too - a stopped VideoStreamPlayer keeps showing its last frame
	# until the next video starts (that's what left skipped videos on screen)
	_player.visible = false
	_card.visible = false
	_current = ""
	_send_done(was)

func _play(vname: String) -> void:
	_release_video_duck()
	_current = vname
	var path := VIDEO_PATH % vname
	if ResourceLoader.exists(path):
		_card.visible = false
		_player.stream = load(path)
		_player.visible = true
		_player.volume_db = video_duck_db if _voice_active else 0.0
		_player.play()
		_duck_music(_player.get_stream_length())
		_send_started(vname)
	else:
		_player.stop()
		_player.visible = false
		_card_label.text = "[ %s ]" % vname
		_card.visible = true
		_card_time = placeholder_seconds
		_send_started(vname)

func _process(delta: float) -> void:
	# Duck the video's own sound while a voice callout is playing
	_voice_check -= delta
	if _voice_check <= 0.0:
		_voice_check = 0.1
		_voice_active = _voice_playing()
	if _player.is_playing():
		var target := video_duck_db if _voice_active else 0.0
		_player.volume_db = move_toward(_player.volume_db, target, delta * 60.0)
	if _card.visible and _current != "":
		_card_time -= delta
		if _card_time <= 0.0:
			_card.visible = false
			_on_finished()

func _on_finished() -> void:
	var done := _current
	_release_video_duck()
	_current = ""
	_player.visible = false
	if done != "":
		_send_done(done)
	if _pending != "":
		var nxt := _pending
		_pending = ""
		_play(nxt)

## Music ducks while the video plays. The duck is timed to the video's
## length as a safety net, but it is released as soon as the video ends, is
## skipped, or is replaced. (Before, a skipped video left its duck in place
## for the full length of the video - e.g. 62s after skipping the intro - and
## GMC lets the WEAKEST active duck win, so callout ducks then never applied
## or released properly and the music stayed low until the next video.)
func _duck_music(seconds: float) -> void:
	var bus = _music_bus()
	if bus == null or music_duck_under_video <= 0.0:
		return
	var d := DuckSettings.new({"attenuation": music_duck_under_video, "attack": 0.3,
		"release": 0.8, "release_from_start": maxf(seconds, 1.0)})
	d.calculate_release_time(Time.get_ticks_msec())
	_video_duck = d
	bus.duck(d)

func _release_video_duck() -> void:
	if _video_duck == null:
		return
	var d := _video_duck
	_video_duck = null
	var bus = _music_bus()
	if bus == null or not d in bus.duckings:
		return
	var timer: Timer = bus._duck_release_timer
	if timer and timer.has_meta("ducking") and timer.get_meta("ducking") == d:
		# This duck owns GMC's release timer: release it now (GMC then moves on
		# to any other duck still running, e.g. a callout)
		timer.stop()
		bus.duck_release()
	else:
		# Not the one being timed: just drop it from the stack
		bus.duckings.erase(d)

func _music_bus():
	if not MPF or not MPF.media or not MPF.media.sound:
		return null
	return MPF.media.sound.get_bus("music")

func _voice_playing() -> bool:
	for n in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		var a := n as AudioStreamPlayer
		if a and a.playing and String(a.bus) == voice_bus:
			return true
	return false

func _send_started(vname: String) -> void:
	if MPF and MPF.server:
		MPF.server.send_event_with_args("fb_video_started", {"video": vname})

func _send_done(vname: String) -> void:
	if MPF and MPF.server:
		MPF.server.send_event_with_args("fb_video_done", {"video": vname})
