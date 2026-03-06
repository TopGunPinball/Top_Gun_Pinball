extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

## Mystery Award — Dog Tag Zoom Animation
## Starts with full pilot image held for 3 seconds, then zooms + pans + rotates into the dog tags.
## Voice callout fires externally at the 3s mark (mystery_voice_callout_start event → base.yaml).
## Award text appears "stamped" on the tag face once zoomed in.
## Reads mystery_award_id (1-14) from player variables to display the correct award.
##
## Required texture (assign via Inspector in Godot editor):
##   - pilot_texture: mystery_background.png (2000x1123 pilot with dog tags)
##
## Animation timeline (matches 11-second display timer + eject delay in mystery_award.yaml):
##   0.0 - 3.0s:  Full image hold (base slide, no movement)
##   3.0s:        mystery_voice_callout_start fires externally → voice plays, zoom begins
##   3.0 - 6.0s:  Zoom + pan + rotate to dog tag (3.0s, eased)
##   5.5 - 6.0s:  Text fades in (overlaps end of zoom)
##   6.2 - 6.7s:  Metallic glint sweeps across text
##   6.0 - 11.0s: Hold with zoomed dog tag and text visible (5-second final hold)
##   11.0s:       MPF timer complete → barrier_drop (handled in mystery_award.yaml)
##   ~12.3s:      MPF eject delay complete → mode stops → ball released

# ═══════ DOG TAG COORDINATES (in original image pixels) ═══════
# Center of the lower dog tag — measured from actual mystery_background.png
# Tag bounding box: top-left ~(1953, 1260), bottom-right ~(1993, 1340)
# If zoom target is still off, re-measure center pixel in your image editor.
const TAG_CX: float = 1973.0
const TAG_CY: float = 1300.0

# ═══════ ANIMATION TIMING (seconds) ═══════
const HOLD_BEFORE: float = 3.0       # 3-second hold on full image before zoom starts
const ZOOM_DURATION: float = 3.0     # Slow, deliberate zoom/pan/rotate (was 1.7s)
const TEXT_FADE_START: float = 5.5   # Text begins appearing 0.5s before zoom completes
const TEXT_FADE_DUR: float = 0.5     # Text fade-in duration
const GLINT_START: float = 6.2       # Metallic glint sweep starts 0.2s after zoom settles
const GLINT_DUR: float = 0.5         # Glint sweep duration

# ═══════ ZOOM / ROTATION TARGETS ═══════
const END_ZOOM: float = 8.5          # Final zoom multiplier
const END_ROTATION_DEG: float = 90.0 # Clockwise rotation to make tag horizontal

# ═══════ TEXT SIZING ═══════
const HEADER_SIZE: int = 22        # "MYSTERY AWARD" header
const LINE1_SIZE: int = 42         # Primary award text
const LINE2_SIZE: int = 38         # Secondary award text (if present)
const SINGLE_LINE_SIZE: int = 46   # Single-line awards (larger)

# ═══════ INTERNAL STATE ═══════
var elapsed: float = 0.0
var df: Font

# ═══════ EXPORTED TEXTURE ═══════
@export var pilot_texture: Texture2D

# ═══════ AWARD DISPLAY TEXT ═══════
# { award_id: [line1, line2] }
const AWARDS: Dictionary = {
	1:  ["LIGHT PILOT", "MISSION"],
	2:  ["LIGHT TRAINING", "MISSION"],
	3:  ["LOCK", "LIT"],
	4:  ["EJECTION SEAT", "QUALIFIED"],
	5:  ["EXTRA BALL", "LIT"],
	6:  ["BONUS", "+ 5X"],
	7:  ["SCORE", "+ 10%"],
	8:  ["30 SECONDS", "BALL SAVE"],
	9:  ["AFTERBURNER PERK", "ACTIVATED"],
	10: ["MISSILES PERK", "ACTIVATED"],
	11: ["WINGMAN PERK", "ACTIVATED"],
	12: ["INVERTED PERK", "ACTIVATED"],
	13: ["REMOVE", "DANGER"],
	14: ["SCORE", "+ 1,000,000"],
}


func _ready() -> void:
	df = ThemeDB.fallback_font


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


# ═══════ MAIN DRAW ═══════
func _draw() -> void:
	var W: float = size.x
	var H: float = size.y

	# Black background (safety — covers any edge gaps during zoom)
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)

	if pilot_texture == null:
		_draw_fallback(W, H)
		return

	var img_w: float = float(pilot_texture.get_width())
	var img_h: float = float(pilot_texture.get_height())

	# ── Calculate animation progress ──
	# raw_t is 0.0 during the HOLD_BEFORE hold, then ramps 0→1 over ZOOM_DURATION
	var raw_t: float = 0.0
	if elapsed > HOLD_BEFORE:
		raw_t = clampf((elapsed - HOLD_BEFORE) / ZOOM_DURATION, 0.0, 1.0)
	var t: float = _smoothstep(raw_t)

	# ── Interpolate zoom and rotation ──
	var fit_scale: float = minf(W / img_w, H / img_h)
	var cur_scale: float = lerpf(fit_scale, END_ZOOM, t)
	var cur_rot: float = deg_to_rad(lerpf(0.0, END_ROTATION_DEG, t))

	# ── Compute draw offset ──
	# Focus point transitions from image center (t=0) to tag center (t=1)
	var focus_x: float = lerpf(img_w * 0.5, TAG_CX, t)
	var focus_y: float = lerpf(img_h * 0.5, TAG_CY, t)

	# Transform: screen_point = offset + Rotate(cur_rot) * (cur_scale * image_point)
	# We want focus point to map to screen center
	var scx: float = W * 0.5
	var scy: float = H * 0.5
	var focus_scaled: Vector2 = Vector2(focus_x, focus_y) * cur_scale
	var cos_r: float = cos(cur_rot)
	var sin_r: float = sin(cur_rot)
	var focus_rot: Vector2 = Vector2(
		focus_scaled.x * cos_r - focus_scaled.y * sin_r,
		focus_scaled.x * sin_r + focus_scaled.y * cos_r
	)
	var draw_offset: Vector2 = Vector2(scx, scy) - focus_rot

	# ── Draw the pilot image (zoomed + rotated) ──
	draw_set_transform(draw_offset, cur_rot, Vector2(cur_scale, cur_scale))
	draw_texture_rect(pilot_texture, Rect2(0, 0, img_w, img_h), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ── Subtle vignette (darkens edges, focuses eye on center) ──
	_draw_vignette(W, H, t)

	# ── Text overlay (fades in near end of zoom) ──
	# NOTE: text is drawn in screen space (rotation=0) so it stays readable
	# regardless of how much the image has been rotated to align the tag.
	var text_alpha: float = clampf((elapsed - TEXT_FADE_START) / TEXT_FADE_DUR, 0.0, 0.8)
	if text_alpha > 0.01:
		_draw_tag_text(W, H, 0.0, text_alpha)
		_draw_glint(W, H, 0.0)


# ═══════ TAG TEXT (engraved on dog tag) ═══════
func _draw_tag_text(W: float, H: float, rotation: float, alpha: float) -> void:
	var award_id: int = _v("mystery_award_id", 1)
	var lines: Array = AWARDS.get(award_id, ["MYSTERY", "AWARD"])

	var cx: float = W * 0.5
	var cy: float = H * 0.5

	# No background panel — text draws directly on the zoomed tag image.
	draw_set_transform(Vector2(cx, cy), rotation, Vector2.ONE)

	# ── "MYSTERY AWARD" header ──
	var header_y: float = -46.0
	_draw_engraved(Vector2(0, header_y), "MYSTERY AWARD", HEADER_SIZE, alpha)

	# ── Divider line ──
	var div_y: float = header_y + 14.0
	var div_w: float = 260.0
	# Groove effect: dark line + light line below
	draw_rect(Rect2(-div_w * 0.5, div_y, div_w, 1),
		Color(0.08, 0.07, 0.06, alpha * 0.6))
	draw_rect(Rect2(-div_w * 0.5, div_y + 1, div_w, 1),
		Color(0.6, 0.58, 0.52, alpha * 0.3))

	# ── Award text ──
	if lines.size() >= 2:
		_draw_engraved(Vector2(0, div_y + 26), lines[0], LINE1_SIZE, alpha)
		_draw_engraved(Vector2(0, div_y + 26 + LINE2_SIZE + 4), lines[1], LINE2_SIZE, alpha)
	else:
		_draw_engraved(Vector2(0, div_y + 30), lines[0], SINGLE_LINE_SIZE, alpha)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ═══════ TEXT EFFECT ═══════
# Dark grey text with soft white highlight above — readable on the light
# metallic dog tag surface without needing a background panel.
func _draw_engraved(center_pos: Vector2, text: String, font_size: int, alpha: float) -> void:
	var w: float = df.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var bp: Vector2 = Vector2(center_pos.x - w * 0.5, center_pos.y)

	# Soft white highlight above (gives depth against the metal surface)
	draw_string(df, bp + Vector2(0, -1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(1.0, 1.0, 1.0, alpha * 0.35))

	# Main text — dark grey, triple-pass for weight
	for ox in [-0.4, 0.0, 0.4]:
		draw_string(df, bp + Vector2(ox, 0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color(0.22, 0.22, 0.22, alpha))


# ═══════ METALLIC GLINT SWEEP ═══════
# A bright highlight that sweeps across the text area after it appears
func _draw_glint(W: float, H: float, rotation: float) -> void:
	if elapsed < GLINT_START or elapsed > GLINT_START + GLINT_DUR + 0.2:
		return

	var gt: float = clampf((elapsed - GLINT_START) / GLINT_DUR, 0.0, 1.0)
	var cx: float = W * 0.5
	var cy: float = H * 0.5

	draw_set_transform(Vector2(cx, cy), rotation, Vector2.ONE)

	# Glint: a narrow bright bar that sweeps left to right across the text area
	var sweep_range: float = 320.0
	var sweep_x: float = lerpf(-sweep_range * 0.5, sweep_range * 0.5, gt)
	var glint_w: float = 40.0
	var glint_h: float = 90.0

	# Fade in and out at edges
	var edge_fade: float = 1.0 - absf(gt - 0.5) * 2.0
	var glint_alpha: float = edge_fade * 0.35

	# Draw gradient glint bar
	for i in range(int(glint_w)):
		var lt: float = float(i) / glint_w
		var bar_alpha: float = sin(lt * PI) * glint_alpha
		draw_rect(Rect2(sweep_x - glint_w * 0.5 + float(i), -glint_h * 0.5, 1, glint_h),
			Color(1.0, 0.97, 0.88, bar_alpha))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ═══════ VIGNETTE (subtle edge darkening during zoom) ═══════
func _draw_vignette(W: float, H: float, zoom_t: float) -> void:
	var intensity: float = zoom_t * 0.4
	if intensity < 0.01:
		return

	var edge: float = 80.0
	for i in range(int(edge)):
		var a: float = (1.0 - float(i) / edge) * intensity
		draw_rect(Rect2(0, float(i), W, 1), Color(0, 0, 0, a))
	for i in range(int(edge)):
		var a: float = (1.0 - float(i) / edge) * intensity
		draw_rect(Rect2(0, H - float(i), W, 1), Color(0, 0, 0, a))
	for i in range(int(edge)):
		var a: float = (1.0 - float(i) / edge) * intensity
		draw_rect(Rect2(float(i), 0, 1, H), Color(0, 0, 0, a * 0.7))
	for i in range(int(edge)):
		var a: float = (1.0 - float(i) / edge) * intensity
		draw_rect(Rect2(W - float(i), 0, 1, H), Color(0, 0, 0, a * 0.7))


# ═══════ FALLBACK (no texture assigned) ═══════
func _draw_fallback(W: float, H: float) -> void:
	var award_id: int = _v("mystery_award_id", 0)
	var lines: Array = AWARDS.get(award_id, ["NO TEXTURE", "ASSIGNED"])
	draw_rect(Rect2(0, 0, W, H), Color(0.1, 0.1, 0.12))
	var p: float = sin(elapsed * 3.0) * 0.12 + 0.88
	_txt_center_bold(Vector2(W * 0.5, H * 0.5 - 30),
		"MYSTERY AWARD", 22, Color(0.9, 0.85, 0.6, p))
	if lines.size() >= 2:
		_txt_center_bold(Vector2(W * 0.5, H * 0.5 + 10),
			lines[0], 28, Color(1.0, 0.95, 0.7, p))
		_txt_center_bold(Vector2(W * 0.5, H * 0.5 + 44),
			lines[1], 26, Color(1.0, 0.95, 0.7, p))
	else:
		_txt_center_bold(Vector2(W * 0.5, H * 0.5 + 15),
			lines[0], 30, Color(1.0, 0.95, 0.7, p))


# ═══════ UTILITY: Smoothstep easing ═══════
func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# ═══════ UTILITY: Read player variable ═══════
func _v(varname: String, fallback: int = 0) -> int:
	if MPF.game and MPF.game.player:
		return int(MPF.game.player.get(varname, fallback))
	return fallback


# ═══════ TEXT HELPERS (matching wingman pattern) ═══════
func _txt_center_bold(pos: Vector2, text: String, sz: int, col: Color) -> void:
	var w: float = df.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var bp: Vector2 = Vector2(pos.x - w * 0.5, pos.y)
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			draw_string(df, bp + Vector2(ox, oy), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
