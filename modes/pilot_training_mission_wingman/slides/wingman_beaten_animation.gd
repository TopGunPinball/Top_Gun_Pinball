extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

## Wingman Training Mission — Live Gameplay HUD (v2.0 — Upgraded)
## Uses sprite images for F-14 jets and MIG targets:
##   - Background image (wingman_background.png)
##   - Two F-14 jets: WINGMAN (zone-shifted) and YOU (follows wingman + position offset)
##   - MIG targets ahead (fixed center with sway)
##   - Top-left HUD: Current Zone + Next Zone
##   - Top-right HUD: Current Distance + Zone Shift countdown
##   - Bottom: Formation gauge bar with red/green gradient, diamond indicator
##   - Engine glow flicker on all aircraft
##   - Green edge flash on good shots, red vignette on bad shots
##   - Win/Loss overlays with draining message at TOP of screen
##
## Required textures (assign via Inspector in Godot editor):
##   - jet_texture: Jet_2.png (F-14 rear view)
##   - mig_texture: mig2.png  (MIG formation)
##   - background_texture: background.png (sky/ocean background)
## NOTE: jet_texture and mig_texture should have transparent backgrounds.
##       If they have black backgrounds, this script removes black at runtime.

const ZONE_NAMES := ["", "LEFT", "MIDDLE", "RIGHT"]
const WINGMAN_SCALE := 0.18  # Base scale for wingman jet
const MIG_SCALE := 0.18      # Small distant MIG targets

# Internal margins to keep content within visible bezel area
const MARGIN_TOP := 30.0
const MARGIN_BOTTOM := 40.0
const MARGIN_LEFT := 28.0
const MARGIN_RIGHT := 28.0

var elapsed := 0.0
var df: Font
var flash_t := 0.0
var flash_color := ""
var zone_local_timer := 0.0
var prev_zone := 2

# Smooth interpolation values
var wm_x_smooth := 0.48      # Wingman X (zone-shifted)
var you_x_smooth := 0.48     # YOU jet X (follows wingman + offset)
var you_y_smooth := 0.55     # YOU jet Y (position-based depth)
var you_scale_smooth := 0.25 # YOU jet scale (position-based)

# Engine flicker: [wm_left, wm_right, you_left, you_right, mig_left, mig_right]
var eng_flicker := [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]

# Processed textures with alpha (black background removed)
var jet_processed: ImageTexture
var mig_processed: ImageTexture

# Assign these in the Godot editor Inspector panel
@export var jet_texture: Texture2D
@export var mig_texture: Texture2D
@export var background_texture: Texture2D


# ═══════ BLACK BACKGROUND REMOVAL ═══════
# Converts black pixels to transparent for images with RGB (no alpha)
# threshold: brightness sum below which pixels become fully transparent
# feather: range above threshold for partial transparency (smooth edges)
func _remove_black_bg(tex: Texture2D, threshold: int, feather: int) -> ImageTexture:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var brightness := int((c.r + c.g + c.b) * 255.0)
			if brightness < threshold:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
			elif brightness < threshold + feather:
				var alpha := float(brightness - threshold) / float(feather)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, alpha))
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	df = ThemeDB.fallback_font
	randomize()
	# Process textures: remove black backgrounds
	# F-14: true black <15, body starts ~60. Conservative threshold.
	jet_processed = _remove_black_bg(jet_texture, 15, 30)
	# MIG: true black <12, body is very dark (25-100). Tight threshold.
	mig_processed = _remove_black_bg(mig_texture, 12, 15)
	MPF.server.add_event_handler("wingman_good_shot", _on_good_shot)
	MPF.server.add_event_handler("wingman_bad_shot", _on_bad_shot)
	MPF.server.add_event_handler("wingman_zone_shifted", _on_zone_shifted)


func _exit_tree() -> void:
	MPF.server.remove_event_handler("wingman_good_shot", _on_good_shot)
	MPF.server.remove_event_handler("wingman_bad_shot", _on_bad_shot)
	MPF.server.remove_event_handler("wingman_zone_shifted", _on_zone_shifted)


func _on_good_shot(_kwargs := {}) -> void:
	flash_t = 0.7
	flash_color = "green"


func _on_bad_shot(_kwargs := {}) -> void:
	flash_t = 0.9
	flash_color = "red"


func _on_zone_shifted(_kwargs := {}) -> void:
	zone_local_timer = 0.0


func _process(delta: float) -> void:
	elapsed += delta
	if flash_t > 0:
		flash_t -= delta

	var mode_active := _v("wingman_mode_active")
	if mode_active == 1:
		zone_local_timer += delta
		if zone_local_timer > 20.0:
			zone_local_timer = 0.0

	var cur_zone := _v("wingman_good_zone", 1)
	if cur_zone != prev_zone:
		prev_zone = cur_zone
		zone_local_timer = 0.0

	# Wingman X target from zone (15% shift left/right)
	var wm_x_target := 0.48
	match cur_zone:
		1: wm_x_target = 0.33   # LEFT
		2: wm_x_target = 0.48   # MIDDLE
		3: wm_x_target = 0.63   # RIGHT
	wm_x_smooth = lerpf(wm_x_smooth, wm_x_target, delta * 2.5)

	# YOU jet position based on wingman_position (-6 to +6)
	var pos := _v("wingman_position")
	var pos_norm := clampf(float(pos + 5) / 10.0, 0.0, 1.0)  # 0 at -5, 1 at +5

	# X: follows wingman + lateral offset (22% at -5, 0% at +5)
	var x_offset := lerpf(0.22, 0.0, pos_norm)
	var you_x_target := wm_x_smooth + x_offset
	you_x_smooth = lerpf(you_x_smooth, you_x_target, delta * 3.0)

	# Y: far back at -5 (0.72), close behind wingman at +5 (0.38)
	var you_y_target := lerpf(0.72, 0.38, pos_norm)
	you_y_smooth = lerpf(you_y_smooth, you_y_target, delta * 3.0)

	# Scale: 175% of wingman at -5, 110% at +5
	var you_scale_target := WINGMAN_SCALE * (1.75 - pos_norm * 0.65)
	you_scale_smooth = lerpf(you_scale_smooth, you_scale_target, delta * 3.0)

	# Update engine flicker
	_update_flicker()

	queue_redraw()


func _update_flicker() -> void:
	for i in range(6):
		eng_flicker[i] = 0.5 + 0.5 * sin(elapsed * 12.7 + float(i) * 2.3) \
			* sin(elapsed * 7.1 + float(i) * 4.1) + randf_range(-0.15, 0.15)
		eng_flicker[i] = clampf(eng_flicker[i], 0.2, 1.0)


# ═══════ DRAW ═══════
func _draw() -> void:
	var W := size.x
	var H := size.y
	var won := _v("wingman_won")
	var lost_bad := _v("wingman_lost_bad_shots_flag")
	var draining := _v("wingman_balls_draining")

	# Background image
	if background_texture:
		draw_texture_rect(background_texture, Rect2(0, 0, W, H), false)

	if won == 1:
		_draw_win_overlay(W, H)
		if draining == 1:
			_draw_draining_message(W, H)
	elif lost_bad == 1:
		_draw_loss_overlay(W, H)
		if draining == 1:
			_draw_draining_message(W, H)
	else:
		_draw_migs(W, H)
		_draw_jets(W, H)
		_draw_flash(W, H)
		_draw_gauge(W, H)
		_draw_hud(W, H)
		if _v("wingman_add_a_ball_ready") == 1:
			_draw_add_a_ball_message(W, H)


# ═══════ MIG TARGETS (fixed center, sway animation) ═══════
func _draw_migs(W: float, H: float) -> void:
	var tex := mig_processed if mig_processed else mig_texture
	if tex == null:
		return
	var src_w := mig_texture.get_width() if mig_texture else tex.get_width()
	var src_h := mig_texture.get_height() if mig_texture else tex.get_height()
	var tex_w := src_w * MIG_SCALE
	var tex_h := src_h * MIG_SCALE
	# Sway: freq_x=0.8, phase_x=0, amp_x=4, freq_y=1.2, phase_y=0, amp_y=2
	var sx := sin(elapsed * 0.8) * 4.0
	var sy := sin(elapsed * 1.2) * 2.0
	var mx := W * 0.48 - tex_w * 0.5 + sx
	var my := H * 0.06 + sy
	draw_texture_rect(tex, Rect2(mx, my, tex_w, tex_h), false)
	# Engine glows
	_draw_engine_glow(Vector2(mx + tex_w * 0.38, my + tex_h * 0.85), MIG_SCALE * 0.7, 4)
	_draw_engine_glow(Vector2(mx + tex_w * 0.62, my + tex_h * 0.85), MIG_SCALE * 0.7, 5)


# ═══════ F-14 JETS ═══════
func _draw_jets(W: float, H: float) -> void:
	var tex := jet_processed if jet_processed else jet_texture
	if tex == null:
		return
	var src_w := jet_texture.get_width() if jet_texture else tex.get_width()
	var src_h := jet_texture.get_height() if jet_texture else tex.get_height()

	# WINGMAN — zone-shifted with sway (freq_x=1.1, phase_x=2.1, amp_x=3)
	var wm_tw := src_w * WINGMAN_SCALE
	var wm_th := src_h * WINGMAN_SCALE
	var wm_cx := W * wm_x_smooth + sin(elapsed * 1.1 + 2.1) * 3.0
	var wm_cy := H * 0.28 + sin(elapsed * 0.9 + 3.7) * 3.0
	var wm_x := wm_cx - wm_tw * 0.5
	var wm_y := wm_cy - wm_th * 0.5
	draw_texture_rect(tex, Rect2(wm_x, wm_y, wm_tw, wm_th), false)
	# Wingman engine glows
	_draw_engine_glow(Vector2(wm_x + wm_tw * 0.43, wm_y + wm_th * 0.95), WINGMAN_SCALE * 1.2, 0)
	_draw_engine_glow(Vector2(wm_x + wm_tw * 0.57, wm_y + wm_th * 0.95), WINGMAN_SCALE * 1.2, 1)

	# YOU — follows wingman + offset, sway (freq_x=0.7, phase_x=4.3, amp_x=5)
	var you_tw := src_w * you_scale_smooth
	var you_th := src_h * you_scale_smooth
	var you_cx := W * you_x_smooth + sin(elapsed * 0.7 + 4.3) * 5.0
	var you_cy := H * you_y_smooth + sin(elapsed * 1.4 + 1.5) * 4.0
	var you_x := you_cx - you_tw * 0.5
	var you_y := you_cy - you_th * 0.5
	draw_texture_rect(tex, Rect2(you_x, you_y, you_tw, you_th), false)
	# You engine glows
	_draw_engine_glow(Vector2(you_x + you_tw * 0.43, you_y + you_th * 0.95), you_scale_smooth * 1.2, 2)
	_draw_engine_glow(Vector2(you_x + you_tw * 0.57, you_y + you_th * 0.95), you_scale_smooth * 1.2, 3)


# ═══════ ENGINE GLOW (3-layer radial) ═══════
func _draw_engine_glow(pos: Vector2, scale: float, idx: int) -> void:
	var f: float = eng_flicker[idx]
	var base_r := 8.0 * scale

	# Outer glow (dim orange)
	for i in range(4, 0, -1):
		var t := float(i) / 4.0
		var r := base_r * 2.0 * t
		draw_circle(pos, r, Color(1.0, 0.63, 0.16, 0.06 * f * (1.0 - t)))

	# Mid flame (bright orange)
	for i in range(3, 0, -1):
		var t := float(i) / 3.0
		var r := base_r * t
		draw_circle(pos, r, Color(1.0, 0.78, 0.31, 0.15 * f * (1.0 - t)))

	# Hot core (white-yellow)
	var core_r := base_r * 0.5
	draw_circle(pos, core_r, Color(1.0, 0.88, 0.47, 0.6 * f))
	draw_circle(pos, core_r * 0.5, Color(1.0, 1.0, 0.86, 0.8 * f))


# ═══════ FORMATION GAUGE (bottom bar) ═══════
func _draw_gauge(W: float, H: float) -> void:
	var pos := _v("wingman_position")
	var gx := MARGIN_LEFT + W * 0.02
	var gy := H - MARGIN_BOTTOM - 38.0
	var gw := W - MARGIN_LEFT - MARGIN_RIGHT - W * 0.04
	var gh := 18.0

	# Panel background (no "FORMATION STATUS" text)
	draw_rect(Rect2(gx - 6, gy - 6, gw + 12, gh + 20), Color(0.02, 0.05, 0.1, 0.8))
	draw_rect(Rect2(gx - 6, gy - 6, gw + 12, gh + 20), Color(0.15, 0.3, 0.45, 0.5), false, 1.0)

	# Bar background
	draw_rect(Rect2(gx, gy, gw, gh), Color(0.03, 0.05, 0.08, 0.95))

	# Red zone left (0-45%) — quadratic falloff toward center
	var red_end := 0.45
	var red_steps := int(gw * red_end)
	for i in range(red_steps):
		var t := float(i) / float(red_steps)
		var fade := (1.0 - t) * (1.0 - t)
		var r_val := lerpf(0.7, 0.05, t)
		var g_val := lerpf(0.08, 0.03, t)
		var b_val := lerpf(0.03, 0.02, t)
		draw_rect(Rect2(gx + i, gy, 1, gh), Color(r_val, g_val, b_val, fade * 0.85))

	# Green zone right (55-100%) — quadratic ramp toward right
	var green_start_pct := 0.55
	var green_start_px := gx + gw * green_start_pct
	var green_steps := int(gw * (1.0 - green_start_pct))
	for i in range(green_steps):
		var t := float(i) / float(green_steps)
		var fade := t * t
		var r_val := lerpf(0.03, 0.05, t)
		var g_val := lerpf(0.04, 0.7, t)
		var b_val := lerpf(0.03, 0.1, t)
		draw_rect(Rect2(green_start_px + i, gy, 1, gh), Color(r_val, g_val, b_val, fade * 0.85))

	# Bar outline
	draw_rect(Rect2(gx, gy, gw, gh), Color(0.2, 0.35, 0.5, 0.35), false, 1.0)

	# Labels
	_txt(Vector2(gx, gy + gh + 11), "LOST", 9, Color(0.8, 0.19, 0.19))
	_txt_right(Vector2(gx + gw, gy + gh + 11), "WIN", 9, Color(0.19, 0.8, 0.31))

	# Diamond indicator
	var imx := gx + ((float(pos) + 6.0) / 12.0) * gw
	var imy := gy + gh * 0.5
	var pulse := sin(elapsed * 5.0) * 0.12 + 0.88
	var mc: Color = Color(0.2, 0.9, 0.5, pulse) if pos >= 0 else Color(1.0, 0.3, 0.2, pulse)

	for gr in range(3, 0, -1):
		draw_circle(Vector2(imx, imy), float(gr) * 6.0,
			Color(mc.r, mc.g, mc.b, 0.06 * pulse))
	draw_colored_polygon(PackedVector2Array([
		Vector2(imx, gy - 2), Vector2(imx + 6, imy),
		Vector2(imx, gy + gh + 2), Vector2(imx - 6, imy)
	]), mc)
	draw_line(Vector2(imx, gy), Vector2(imx, gy + gh),
		Color(mc.r, mc.g, mc.b, 0.7), 1.5)


# ═══════ HUD OVERLAY PANELS ═══════
func _draw_hud(W: float, H: float) -> void:
	var pos := _v("wingman_position")
	var zone := _v("wingman_good_zone", 1)
	var direction := _v("wingman_zone_direction", 1)
	var time_left: float = maxf(0.0, 20.0 - zone_local_timer)

	# Determine next zone
	var next_zone_name := ""
	match zone:
		1: next_zone_name = "MIDDLE"
		2:
			if direction == 1:
				next_zone_name = "RIGHT"
			else:
				next_zone_name = "LEFT"
		3: next_zone_name = "MIDDLE"

	# ─── TOP-LEFT: Current Zone + Next Zone ───
	var tlw := 220.0
	var tlh := 58.0
	_draw_panel(MARGIN_LEFT, MARGIN_TOP, tlw, tlh)

	var zn: String = ZONE_NAMES[clampi(zone, 0, 3)]
	_txt_bold(Vector2(MARGIN_LEFT + 10, MARGIN_TOP + 24), "Current Zone: %s" % zn,
		16, Color(0.16, 0.93, 0.47))
	_txt_bold(Vector2(MARGIN_LEFT + 10, MARGIN_TOP + 48), "Next Zone: %s" % next_zone_name,
		14, Color(1.0, 0.6, 0.0))

	# ─── TOP-RIGHT: Current Distance + Zone Shift ───
	var trw := 220.0
	var trh := 58.0
	var trx := W - MARGIN_RIGHT - trw
	_draw_panel(trx, MARGIN_TOP, trw, trh)

	var pn: String = "+%d" % pos if pos > 0 else str(pos)
	var dist_color := Color(0.16, 0.93, 0.47) if pos >= 0 else Color(0.93, 0.27, 0.27)
	_txt_bold(Vector2(trx + 10, MARGIN_TOP + 24), "Current Distance: %s" % pn,
		16, dist_color)
	_txt_bold(Vector2(trx + 10, MARGIN_TOP + 48), "Zone Shift in: %ds" % int(ceil(time_left)),
		14, Color(1.0, 0.6, 0.0))


func _draw_panel(x: float, y: float, w: float, h: float) -> void:
	draw_rect(Rect2(x, y, w, h), Color(0.02, 0.05, 0.1, 0.78))
	draw_rect(Rect2(x, y, w, h), Color(0.15, 0.3, 0.45, 0.4), false, 1.0)


func _draw_flash(W: float, H: float) -> void:
	if flash_t <= 0:
		return
	var a := flash_t
	if flash_color == "green":
		var edge := 60.0
		for i in range(10):
			var t := float(i) / 10.0
			var al := a * 0.2 * (1.0 - t)
			draw_rect(Rect2(edge * t, 0, 7, H), Color(0.0, 1.0, 0.31, al))
			draw_rect(Rect2(W - edge + edge * t, 0, 7, H),
				Color(0.0, 1.0, 0.31, al * (1.0 - t)))
		draw_rect(Rect2(0, 0, W, H), Color(0.0, 1.0, 0.31, a * 0.03))
	elif flash_color == "red":
		draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.12, 0.04, a * 0.12))
		for i in range(6):
			var t := float(i) / 6.0
			var inset: float = t * minf(W, H) * 0.25
			draw_rect(Rect2(inset, inset, W - inset * 2, H - inset * 2),
				Color(0.63, 0.0, 0.0, a * 0.1 * (1.0 - t)), false, 2.0)


# ═══════ WIN OVERLAY ═══════
func _draw_win_overlay(W: float, H: float) -> void:
	var bank := _v("wingman_points_bank")
	var bad_count := _v("wingman_bad_shots_count")
	var good_count := _v("wingman_good_shots_count")
	var a: float = clampf(elapsed * 0.4, 0.0, 0.85)
	var p := sin(elapsed * 3.0) * 0.12 + 0.88

	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, a))
	for y in range(0, int(H), 3):
		draw_rect(Rect2(0, y, W, 1), Color(0.0, 1.0, 0.31, 0.008 * p))
	_txt_center_bold(Vector2(W * 0.5, H * 0.5 - 22),
		"MISSION COMPLETE", 28, Color(0.16, 1.0, 0.47, p))
	_txt_center(Vector2(W * 0.5, H * 0.5 + 10),
		"WINGMAN PERK ACTIVATED - MB EXTENDER", 11, Color(0.47, 1.0, 0.71, 0.65))
	_txt_center(Vector2(W * 0.5, H * 0.5 + 28),
		"Good: %d  |  Bad: %d" % [good_count, bad_count], 11, Color(0.47, 1.0, 0.71, 0.65))
	_txt_center(Vector2(W * 0.5, H * 0.5 + 48),
		"POINTS: %s" % _comma(bank), 13, Color(1.0, 0.85, 0.2, p))
	if bad_count == 0:
		_txt_center(Vector2(W * 0.5, H * 0.5 + 66),
			"PERFECT RUN BONUS: +1,500,000", 10,
			Color(1.0, 0.9, 0.2, 0.6 + 0.4 * sin(elapsed * 4.0)))


# ═══════ LOSS OVERLAY (bad shots -6) ═══════
func _draw_loss_overlay(W: float, H: float) -> void:
	var bad_count := _v("wingman_bad_shots_count")
	var good_count := _v("wingman_good_shots_count")
	var a: float = clampf(elapsed * 0.4, 0.0, 0.85)
	var p := sin(elapsed * 3.0) * 0.12 + 0.88

	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, a))
	for y in range(0, int(H), 3):
		draw_rect(Rect2(0, y, W, 1), Color(1.0, 0.15, 0.05, 0.008 * p))
	_txt_center_bold(Vector2(W * 0.5, H * 0.5 - 22),
		"MISSION FAILED", 28, Color(1.0, 0.2, 0.15, p))
	_txt_center(Vector2(W * 0.5, H * 0.5 + 10),
		"LOST FORMATION", 11, Color(1.0, 0.5, 0.4, 0.65))
	_txt_center(Vector2(W * 0.5, H * 0.5 + 28),
		"Good: %d  |  Bad: %d" % [good_count, bad_count], 11,
		Color(1.0, 0.5, 0.4, 0.65))
	_txt_center(Vector2(W * 0.5, H * 0.5 + 48),
		"CONSOLATION: 500,000", 13, Color(1.0, 0.85, 0.2, p))


# ═══════ BALLS DRAINING MESSAGE (TOP of screen, large and clear) ═══════
func _draw_draining_message(W: float, H: float) -> void:
	var p := sin(elapsed * 2.5) * 0.15 + 0.85
	# Full-width bar at TOP of screen
	draw_rect(Rect2(0, 0, W, 48), Color(0.0, 0.0, 0.0, 0.85))
	draw_rect(Rect2(0, 47, W, 2), Color(1.0, 0.8, 0.2, 0.6))
	_txt_center_bold(Vector2(W * 0.5, 20),
		"BALLS DRAINING", 18, Color(1.0, 0.9, 0.3, p))
	_txt_center_bold(Vector2(W * 0.5, 40),
		"DON'T GO ANYWHERE - YOUR GAME WILL CONTINUE SHORTLY",
		11, Color(1.0, 0.9, 0.3, p * 0.8))


# ═══════ ADD-A-BALL READY MESSAGE ═══════
func _draw_add_a_ball_message(W: float, H: float) -> void:
	var p := sin(elapsed * 3.0) * 0.2 + 0.8
	var bar_y := H - MARGIN_BOTTOM - 72.0
	draw_rect(Rect2(0, bar_y, W, 22), Color(0.0, 0.0, 0.0, 0.75))
	draw_rect(Rect2(0, bar_y, W, 1), Color(1.0, 0.6, 0.0, 0.5))
	draw_rect(Rect2(0, bar_y + 21, W, 1), Color(1.0, 0.6, 0.0, 0.5))
	_txt_center_bold(Vector2(W * 0.5, bar_y + 16),
		"ADD A BALL READY - HIT PILOT GEAR TARGET TO ACTIVATE",
		10, Color(1.0, 0.65, 0.0, p))


# ═══════ TEXT HELPERS ═══════
func _txt(pos: Vector2, text: String, sz: int, col: Color) -> void:
	draw_string(df, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _txt_bold(pos: Vector2, text: String, sz: int, col: Color) -> void:
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			draw_string(df, pos + Vector2(ox, oy), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _txt_center(pos: Vector2, text: String, sz: int, col: Color) -> void:
	var w := df.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(df, Vector2(pos.x - w * 0.5, pos.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _txt_center_bold(pos: Vector2, text: String, sz: int, col: Color) -> void:
	var w := df.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var bp := Vector2(pos.x - w * 0.5, pos.y)
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			draw_string(df, bp + Vector2(ox, oy), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _txt_right(pos: Vector2, text: String, sz: int, col: Color) -> void:
	var w := df.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(df, Vector2(pos.x - w, pos.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _comma(v: int) -> String:
	var s := str(v)
	var r := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0 and s[i] != "-":
			r += ","
		r += s[i]
	return r


func _v(varname: String, fallback: int = 0) -> int:
	if MPF.game and MPF.game.player:
		return int(MPF.game.player.get(varname, fallback))
	return fallback
