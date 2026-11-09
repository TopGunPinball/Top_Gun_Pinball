extends VideoStreamPlayer
## MAVERICK & PENNY - looping background video for part 1 (penny_background
## slide). Silent video, so it never fights the music. If the file is missing
## the slide is simply empty (no error card).

const VIDEO_PATH := "res://addons/artwork/videos/hard_deck_penny/penny_background.ogv"

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not ResourceLoader.exists(VIDEO_PATH):
		visible = false
		return
	stream = load(VIDEO_PATH)
	loop = true
	volume_db = -80.0
	play()
	# Belt and braces: restart if a Godot build ignores `loop`
	finished.connect(func(): play())
