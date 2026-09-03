extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

## Wingman Victory Mode HUD
##
## Mirrors the main tug-of-war HUD's jet/mig setup:
##   - MIG target, roughly centered with a small idle sway
##   - WINGMAN jet (top), sways together with the MIG (no zone concept in
##     victory mode, so it stays centered rather than shifting left/right)
##   - YOU jet (bottom, the player), closes in on / falls back from the
##     WINGMAN jet based on current_player.wingman_victory_position (1-6:
##     1 = furthest away, 6 = right on the wing) - same distance/scale
##     formula as the main HUD, just rescaled from the 1-6 range instead
##     of -6..+6.
##
## On top of the jets, toggles between two child containers based on
## current_player.wingman_victory_jackpot_ready:
##   Victory base script      <- visible while shooting for the next shot (0)
##   Victory Super Jackpot    <- visible once all 9 shots are collected (1)
##
## Required textures (assign via Inspector):
##   jet_texture -> Jet 2.png
##   mig_texture -> mig2.png
##   background_texture -> background.png

const WINGMAN_SCALE := 0.18
const MIG_SCALE := 0.18

@export var jet_texture: Texture2D
@export var mig_texture: Texture2D
@export var background_texture: Texture2D

@onready var base_view: Node = $"Victory base script"
@onready var jackpot_view: Node = $"Victory Super Jackpot"

var jet_processed: ImageTexture
var mig_processed: ImageTexture

var elapsed := 0.0
var flash_t := 0.0
var flash_color := ""

# Smooth interpolation values (same roles as the main HUD)
var wm_x_smooth := 0.48
var you_x_smooth := 0.48
var you_y_smooth := 0.55
var you_scale_smooth := 0.25

# Engine flicker: [wm_left, wm_right, you_left, you_right, mig_left, mig_right]
var eng_flicker := [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]


# ═══════ BLACK BACKGROUND REMOVAL (same approach as wingman_beaten_animation.gd) ═══════
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
  randomize()
  jet_processed = _remove_black_bg(jet_texture, 15, 30)
  mig_processed = _remove_black_bg(mig_texture, 12, 15)

  MPF.server.add_event_handler("wingman_victory_start", _on_victory_state_changed)
  MPF.server.add_event_handler("wingman_victory_all_collected", _on_victory_state_changed)
  MPF.server.add_event_handler("wingman_victory_jackpot_hit", _on_victory_state_changed)
  MPF.server.add_event_handler("wingman_victory_good_shot", _on_good_shot)
  MPF.server.add_event_handler("wingman_victory_bad_shot_position", _on_bad_shot)

  _update_visibility()


func _exit_tree() -> void:
  MPF.server.remove_event_handler("wingman_victory_start", _on_victory_state_changed)
  MPF.server.remove_event_handler("wingman_victory_all_collected", _on_victory_state_changed)
  MPF.server.remove_event_handler("wingman_victory_jackpot_hit", _on_victory_state_changed)
  MPF.server.remove_event_handler("wingman_victory_good_shot", _on_good_shot)
  MPF.server.remove_event_handler("wingman_victory_bad_shot_position", _on_bad_shot)


func _on_victory_state_changed(_kwargs := {}) -> void:
  _update_visibility()


func _on_good_shot(_kwargs := {}) -> void:
  flash_t = 0.7
  flash_color = "lightblue"


func _on_bad_shot(_kwargs := {}) -> void:
  flash_t = 0.9
  flash_color = "red"


func _update_visibility() -> void:
  var jackpot_ready := _v("wingman_victory_jackpot_ready")
  if base_view:
    base_view.visible = (jackpot_ready == 0)
  if jackpot_view:
    jackpot_view.visible = (jackpot_ready == 1)


func _process(delta: float) -> void:
  elapsed += delta
  if flash_t > 0:
    flash_t -= delta

  # WINGMAN jet stays centered - no zone concept in victory mode - but
  # shares the same idle sway as the MIG so they visibly move together.
  wm_x_smooth = lerpf(wm_x_smooth, 0.48, delta * 2.5)

  # YOU jet position based on wingman_victory_position (1-6)
  var pos: int = clampi(_v("wingman_victory_position", 6), 1, 6)
  var pos_norm := float(pos - 1) / 5.0  # 0 at pos=1 (far), 1 at pos=6 (on the wing)

  var x_offset := lerpf(0.22, 0.0, pos_norm)
  var you_x_target := wm_x_smooth + x_offset
  you_x_smooth = lerpf(you_x_smooth, you_x_target, delta * 3.0)

  var you_y_target := lerpf(0.72, 0.38, pos_norm)
  you_y_smooth = lerpf(you_y_smooth, you_y_target, delta * 3.0)

  var you_scale_target := WINGMAN_SCALE * (1.75 - pos_norm * 0.65)
  you_scale_smooth = lerpf(you_scale_smooth, you_scale_target, delta * 3.0)

  _update_flicker()
  queue_redraw()


func _update_flicker() -> void:
  for i in range(6):
    eng_flicker[i] = 0.5 + 0.5 * sin(elapsed * 12.7 + float(i) * 2.3) \
      * sin(elapsed * 7.1 + float(i) * 4.1) + randf_range(-0.15, 0.15)
    eng_flicker[i] = clampf(eng_flicker[i], 0.2, 1.0)


func _draw() -> void:
  var w := size.x
  var h := size.y

  _draw_background(w, h)
  _draw_migs(w, h)
  _draw_jets(w, h)
  _draw_flash(w, h)


func _draw_background(w: float, h: float) -> void:
  if background_texture:
    draw_texture_rect(background_texture, Rect2(0, 0, w, h), false)


# ═══════ MIG TARGET (roughly centered, sway animation) ═══════
func _draw_migs(w: float, h: float) -> void:
  var tex := mig_processed if mig_processed else mig_texture
  if tex == null:
    return
  var src_w := mig_texture.get_width() if mig_texture else tex.get_width()
  var src_h := mig_texture.get_height() if mig_texture else tex.get_height()
  var tex_w := src_w * MIG_SCALE
  var tex_h := src_h * MIG_SCALE
  # Same sway as the WINGMAN jet so they read as moving together
  var sx := sin(elapsed * 0.8) * 4.0
  var sy := sin(elapsed * 1.2) * 2.0
  var mx := w * 0.48 - tex_w * 0.5 + sx
  var my := h * 0.06 + sy
  draw_texture_rect(tex, Rect2(mx, my, tex_w, tex_h), false)
  _draw_engine_glow(Vector2(mx + tex_w * 0.38, my + tex_h * 0.85), MIG_SCALE * 0.7, 4)
  _draw_engine_glow(Vector2(mx + tex_w * 0.62, my + tex_h * 0.85), MIG_SCALE * 0.7, 5)


# ═══════ F-14 JETS (WINGMAN top, YOU bottom) ═══════
func _draw_jets(w: float, h: float) -> void:
  var tex := jet_processed if jet_processed else jet_texture
  if tex == null:
    return
  var src_w := jet_texture.get_width() if jet_texture else tex.get_width()
  var src_h := jet_texture.get_height() if jet_texture else tex.get_height()

  # WINGMAN - centered, sways together with the MIG
  var wm_tw := src_w * WINGMAN_SCALE
  var wm_th := src_h * WINGMAN_SCALE
  var wm_cx := w * wm_x_smooth + sin(elapsed * 1.1 + 2.1) * 3.0
  var wm_cy := h * 0.28 + sin(elapsed * 0.9 + 3.7) * 3.0
  var wm_x := wm_cx - wm_tw * 0.5
  var wm_y := wm_cy - wm_th * 0.5
  draw_texture_rect(tex, Rect2(wm_x, wm_y, wm_tw, wm_th), false)
  _draw_engine_glow(Vector2(wm_x + wm_tw * 0.43, wm_y + wm_th * 0.95), WINGMAN_SCALE * 1.2, 0)
  _draw_engine_glow(Vector2(wm_x + wm_tw * 0.57, wm_y + wm_th * 0.95), WINGMAN_SCALE * 1.2, 1)

  # YOU - closes in on / falls back from WINGMAN based on victory position
  var you_tw := src_w * you_scale_smooth
  var you_th := src_h * you_scale_smooth
  var you_cx := w * you_x_smooth + sin(elapsed * 0.7 + 4.3) * 5.0
  var you_cy := h * you_y_smooth + sin(elapsed * 1.4 + 1.5) * 4.0
  var you_x := you_cx - you_tw * 0.5
  var you_y := you_cy - you_th * 0.5
  draw_texture_rect(tex, Rect2(you_x, you_y, you_tw, you_th), false)
  _draw_engine_glow(Vector2(you_x + you_tw * 0.43, you_y + you_th * 0.95), you_scale_smooth * 1.2, 2)
  _draw_engine_glow(Vector2(you_x + you_tw * 0.57, you_y + you_th * 0.95), you_scale_smooth * 1.2, 3)


# ═══════ ENGINE GLOW (3-layer radial) ═══════
func _draw_engine_glow(pos: Vector2, scale: float, idx: int) -> void:
  var f: float = eng_flicker[idx]
  var base_r := 8.0 * scale

  for i in range(4, 0, -1):
    var t := float(i) / 4.0
    var r := base_r * 2.0 * t
    draw_circle(pos, r, Color(1.0, 0.63, 0.16, 0.06 * f * (1.0 - t)))

  for i in range(3, 0, -1):
    var t := float(i) / 3.0
    var r := base_r * t
    draw_circle(pos, r, Color(1.0, 0.78, 0.31, 0.15 * f * (1.0 - t)))

  var core_r := base_r * 0.5
  draw_circle(pos, core_r, Color(1.0, 0.88, 0.47, 0.6 * f))
  draw_circle(pos, core_r * 0.5, Color(1.0, 1.0, 0.86, 0.8 * f))


func _draw_flash(w: float, h: float) -> void:
  if flash_t <= 0:
    return
  var a := flash_t
  var c: Color
  if flash_color == "lightblue":
    c = Color(0.4, 0.75, 1.0, a * 0.2)
  else:
    c = Color(1.0, 0.15, 0.1, a * 0.2)
  draw_rect(Rect2(0, 0, w, h), c)


func _v(varname: String, fallback: int = 0) -> int:
  if MPF.game and MPF.game.player:
    return int(MPF.game.player.get(varname, fallback))
  return fallback
