extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

##############################################################################
## CARRIER LANDING VIDEO MODE (prototype v4 - realistic 3D)
## File: modes/carrier_landing/slides/carrier_landing.gd
## ATTACH TO: root node of carrier_landing.tscn
##
## Real-time 3D scene (sky, ocean, carrier, lighting) built entirely in code,
## with a 2D cockpit, HUD and instrument panel drawn over it.
## Designed for the Mobile renderer (Vulkan). No external assets.
##
## LEVELS: 1 = DAY, 2 = DAY / ROUGH SEAS, 3 = NIGHT (each faster, windier, tighter window)
##
## PLAYER CONTROLS (flippers only):
##   Hold LEFT / RIGHT flipper  -> steer against the crosswind (lineup)
##   Press BOTH flippers        -> drop the hook (only during the hook window)
##
## MPF -> GODOT events (listened for here):
##   landing_begin {level: 1-3}                     start the landing
##   s_flipper_left_active / _inactive              steering input
##   s_flipper_right_active / _inactive             steering input
##
## GODOT -> MPF events (posted from here):
##   landing_result_wire_3 / wire_2 / wire_4 / wire_1
##   landing_result_bolter / landing_result_waveoff / landing_result_crash
##   landing_done                                   result screen finished
##   landing_sfx_*                                  sound cues (see _ev calls)
##
## Scores shown here are DISPLAY ONLY. MPF will do the real scoring.
##############################################################################

class Overlay extends Control:
	var host
	func _draw() -> void:
		if host:
			host._draw_overlay(self)

enum St { WAIT, INTRO, APPROACH, WINDOW, COMMITTED, TOUCHDOWN, RESULT, DONE }

const LEVELS := {
	1: {"speed": 60.0, "app_time": 14.0, "wind": 1.8, "gust": 0.0, "p1": 1.25, "a2": 0.0, "p2": 1.0, "win": 1.0, "start_off": 8.0},
	2: {"speed": 70.0, "app_time": 12.0, "wind": 2.8, "gust": 1.0, "p1": 0.95, "a2": 0.0, "p2": 1.0, "win": 1.0, "start_off": 12.0},
	3: {"speed": 80.0, "app_time": 10.0, "wind": 3.6, "gust": 1.5, "p1": 0.65, "a2": 0.0, "p2": 1.0, "win": 1.0, "start_off": 16.0},
}
const LEVEL_MULT := {1: 1.0, 2: 1.5, 3: 2.0}
const LEVEL_NAME := {1: "DAY TRAP", 2: "ROUGH SEAS", 3: "NIGHT TRAP"}

const RESULTS := {
	"wire_3":  {"title": "3-WIRE!",   "sub": "PERFECT LANDING!",          "award": 5000000},
	"wire_2":  {"title": "2-WIRE",    "sub": "GOOD LANDING - A LITTLE EARLY",        "award": 3000000},
	"wire_4":  {"title": "4-WIRE",    "sub": "GOOD LANDING - A LITTLE LATE",       "award": 3000000},
	"wire_1":  {"title": "1-WIRE",    "sub": "ROUGH LANDING - TOO EARLY",      "award": 1500000},
	"bolter":  {"title": "BOLTER!",   "sub": "MISSED THE WIRES - TOO LATE", "award": 500000},
	"waveoff": {"title": "WAVE OFF!", "sub": "TOO FAR OFF LINEUP",              "award": 250000},
	"crash":   {"title": "CRASH!",    "sub": "",                                "award": 0},
	"splash":  {"title": "SPLASH!",   "sub": "MISSED THE CARRIER - YOU'RE IN THE DRINK", "award": 0},
}

# Crash particle space (kept from the 2D versions; overlay scales x4)
const LW := 320.0
const LH := 180.0

# --- World (meters). Landing coords: x = lateral from lane centerline, z = forward from ramp ---
const DECK_H := 20.0
const EYE_TD := 3.5
const GLIDE := 0.08
const HEAVE_M := 2.0
const WIRE_Z := [36.0, 48.0, 60.0, 72.0]
const LANE_LEN := 215.0
const HOOK_WINDOW := 5.0      # seconds the player has to press both flippers
const CALL_BALL_LEAD := 3.0   # "call the ball" voice this many seconds before the window
const COMMIT_TIME := 0.9      # after pressing, the jet reaches the deck this fast
# Landing meter (the ball), -1 = bottom .. +1 = top:
const Z_CRASH := -0.5         # below this: ramp strike (crash into the back of the carrier)
const Z_EARLY1 := -0.35       # -0.5..-0.35 = 1-wire, -0.35..-0.2 = 2-wire
const Z_PERFECT := 0.2        # -0.2..0.2 = 3-wire (perfect)
const Z_LATE := 0.5           # 0.2..0.5 = 4-wire; above 0.5 = missed late (bolter)
const LANE_HALF := 12.0
const X_CRASH := 26.0
const X_WAVEOFF := 55.0       # display range only (no automatic wave-off any more)
# Steering: flippers roll the jet; bank angle pulls it sideways; drift carries on
const MAX_BANK := 0.349       # 20 degrees
const ROLL_RATE := 0.60       # rad/s  (~0.6 s to full bank)
const BANK_ACC := 5.0         # m/s^2 sideways at full bank
const DRIFT_DRAG := 0.40      # how quickly sideways drift dies away
const STEER_ACC := 16.0
const STEER_DAMP := 2.2
const DECK_ANGLE := 9.0

const INTRO_TIME := 4.0
const WAIT_FALLBACK := 5.0
const RESULT_TIME := 2.5

# --- Camera ---
const CAM_FOV := 30.0
const CAM_PITCH := -7.0       # degrees; looking slightly down the glide path
const PX_PER_DEG := 24.0      # 720 px / 30 degrees

# --- Ship geometry (ship coords: xs = starboard +, zs = forward from stern) ---
const DECK_OUTLINE := [Vector2(-20, 0), Vector2(22, 0), Vector2(24, 20), Vector2(24, 140), Vector2(34, 150),
	Vector2(34, 225), Vector2(24, 235), Vector2(22, 300), Vector2(12, 330), Vector2(-8, 330), Vector2(-18, 285),
	Vector2(-22, 245), Vector2(-44, 236), Vector2(-54, 222)]
const HULL_OUTLINE := [Vector2(-15, 3), Vector2(17, 3), Vector2(21, 40), Vector2(21, 280), Vector2(11, 326),
	Vector2(-7, 326), Vector2(-17, 280), Vector2(-19, 40)]
const ISLAND_BOXES := [
	[24.0, 33.0, 158.0, 206.0, 0.0, 22.0],
	[25.0, 32.5, 163.0, 200.0, 22.0, 28.0],
	[26.0, 31.5, 169.0, 194.0, 28.0, 34.0],
	[27.0, 31.0, 184.0, 193.0, 34.0, 38.5],
]
const PARKED := [[15.0, 45.0], [17.0, 66.0], [15.0, 250.0], [7.0, 268.0], [17.0, 275.0], [4.0, 290.0], [14.0, 300.0], [18.0, 222.0]]
const TIRE_MARKS := [[-3.0, 28.0, 30.0], [2.5, 34.0, 38.0], [-1.0, 44.0, 26.0], [4.5, 52.0, 30.0], [-5.0, 60.0, 22.0], [0.8, 70.0, 34.0], [-2.2, 82.0, 28.0]]

# --- Lighting / atmosphere per level ---
const PAL := {
	1: {"zenith": Color(0.10, 0.26, 0.66), "horizon": Color(0.58, 0.72, 0.9), "below": Color(0.2, 0.3, 0.45),
		"sun_col": Color(1.0, 0.96, 0.88), "sun_energy": 1.4, "sun_rot": Vector3(-34, -62, 0), "sun_size": 0.9994,
		"glow": Color(1.0, 0.9, 0.7), "glow_amt": 0.35, "stars": 0.0, "clouds": 0.55,
		"cloud_lit": Color(1, 1, 1), "cloud_dark": Color(0.62, 0.68, 0.78), "light_col": Color(1.0, 0.96, 0.9), "light_energy": 1.3,
		"ambient": 0.55, "fog": Color(0.62, 0.74, 0.9), "fog_density": 0.00011, "water": Color(0.01, 0.06, 0.14), "water_far": Color(0.05, 0.13, 0.24),
		"night": false, "exposure": 1.0, "swell": 0.5, "chop": 1.0},
	2: {"zenith": Color(0.14, 0.26, 0.52), "horizon": Color(0.62, 0.7, 0.8), "below": Color(0.2, 0.26, 0.34),
		"sun_col": Color(1.0, 0.97, 0.9), "sun_energy": 1.2, "sun_rot": Vector3(-46, -40, 0), "sun_size": 0.9994,
		"glow": Color(1.0, 0.92, 0.8), "glow_amt": 0.25, "stars": 0.0, "clouds": 0.85,
		"cloud_lit": Color(0.92, 0.94, 0.97), "cloud_dark": Color(0.45, 0.5, 0.58), "light_col": Color(0.95, 0.95, 0.95), "light_energy": 1.05,
		"ambient": 0.6, "fog": Color(0.6, 0.67, 0.76), "fog_density": 0.00016, "water": Color(0.015, 0.06, 0.12), "water_far": Color(0.08, 0.15, 0.24),
		"night": false, "exposure": 1.0, "swell": 1.1, "chop": 1.6},
	3: {"zenith": Color(0.004, 0.008, 0.025), "horizon": Color(0.03, 0.05, 0.10), "below": Color(0.01, 0.015, 0.03),
		"sun_col": Color(0.9, 0.92, 1.0), "sun_energy": 1.2, "sun_rot": Vector3(-28, 150, 0), "sun_size": 0.99975,
		"glow": Color(0.5, 0.6, 0.9), "glow_amt": 0.25, "stars": 1.0, "clouds": 0.0,
		"cloud_lit": Color(0.2, 0.22, 0.3), "cloud_dark": Color(0.05, 0.06, 0.1), "light_col": Color(0.55, 0.65, 1.0), "light_energy": 0.22,
		"ambient": 0.25, "fog": Color(0.03, 0.05, 0.1), "fog_density": 0.00025, "water": Color(0.005, 0.01, 0.025), "water_far": Color(0.02, 0.04, 0.08),
		"night": true, "exposure": 1.3, "swell": 0.6, "chop": 1.0},
}

# --- State ---
var st: int = St.WAIT
var st_t := 0.0
var tt := 0.0
var level := 1
var cfg: Dictionary = LEVELS[1]
var pal: Dictionary = PAL[1]

var dist := 1000.0
var spd := 60.0
var travelled := 0.0
var px := 0.0
var pv := 0.0
var wind := 0.0
var wind_p1 := 0.0
var wind_p2 := 0.0
var gust := 0.0
var gust_t := 3.0
var extra_alt := 0.0
var pitch_px := 0.0
var d0 := 1000.0

var sw_left := false
var sw_right := false

var result := ""
var crash_reason := ""
var td_zc := 60.0
var hook_down := false
var shake := 0.0
var flash := 0.0
var jolt := 0.0
var warn_t := 0.0
var particles := []
var fireball_t := -1.0
var cracks := []
var roll := 0.0
var wind_dir := 1.0
var gust_target := 0.0
var splash_t := -1.0
var splash_start_alt := 0.0
var water_parts := []
var flash_col := Color(1, 0.85, 0.6)
var d_window := 240.0
var move_spd := 60.0
var voice_called := false

# --- 3D scene ---
var deck_l := PackedVector2Array()
var hull_l := PackedVector2Array()
var island_l := []
var overlay: Overlay
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var water_mat: ShaderMaterial
var wake_mat: ShaderMaterial
var ocean: MeshInstance3D
var carrier: Node3D
var radar: MeshInstance3D
var beacon: MeshInstance3D
var night_lights: Node3D
var win_mat: StandardMaterial3D
var deck_bb := Rect2()
const PPM := 4.0

##############################################################################
## LIFECYCLE
##############################################################################

func _ready() -> void:
	randomize()
	wind_p1 = randf() * TAU
	wind_p2 = randf() * TAU
	deck_l = _outline_to_land(DECK_OUTLINE)
	hull_l = _outline_to_land(HULL_OUTLINE)
	for b in ISLAND_BOXES:
		island_l.append([_ship_rect(b[0], b[1], b[2], b[3]), float(b[4]), float(b[5])])
	_build_scene()
	overlay = Overlay.new()
	overlay.host = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	MPF.server.add_event_handler("landing_begin", _on_begin)
	MPF.server.add_event_handler("s_flipper_left_active", _on_left_on)
	MPF.server.add_event_handler("s_flipper_left_inactive", _on_left_off)
	MPF.server.add_event_handler("s_flipper_right_active", _on_right_on)
	MPF.server.add_event_handler("s_flipper_right_inactive", _on_right_off)
	_set_level(_machine_level())
	dist = d0
	_update_frame()

func _exit_tree() -> void:
	MPF.server.remove_event_handler("landing_begin", _on_begin)
	MPF.server.remove_event_handler("s_flipper_left_active", _on_left_on)
	MPF.server.remove_event_handler("s_flipper_left_inactive", _on_left_off)
	MPF.server.remove_event_handler("s_flipper_right_active", _on_right_on)
	MPF.server.remove_event_handler("s_flipper_right_inactive", _on_right_off)
	super()

func _ship_to_land(xs: float, zs: float) -> Vector2:
	var a := deg_to_rad(DECK_ANGLE)
	return Vector2((xs + 4.0) * cos(a) + zs * sin(a), -(xs + 4.0) * sin(a) + zs * cos(a))

func _outline_to_land(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_ship_to_land(p.x, p.y))
	return out

func _ship_rect(xs0: float, xs1: float, zs0: float, zs1: float) -> PackedVector2Array:
	return _outline_to_land([Vector2(xs0, zs0), Vector2(xs1, zs0), Vector2(xs1, zs1), Vector2(xs0, zs1)])

##############################################################################
## SHADERS
##############################################################################

const SKY_SHADER := """
shader_type sky;
uniform vec3 zenith : source_color;
uniform vec3 horizon : source_color;
uniform vec3 below : source_color;
uniform vec3 sun_color : source_color;
uniform float sun_energy = 1.0;
uniform float sun_size = 0.9994;
uniform vec3 glow_color : source_color;
uniform float glow_amt = 0.3;
uniform float stars = 0.0;
uniform float clouds = 0.0;
uniform vec3 cloud_lit : source_color;
uniform vec3 cloud_dark : source_color;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col;
	if (y >= 0.0) { col = mix(horizon, zenith, pow(y, 0.45)); }
	else { col = mix(horizon, below, clamp(-y * 8.0, 0.0, 1.0)); }
	float sd = dot(d, LIGHT0_DIRECTION);
	float hz = 1.0 - clamp(abs(y) * 3.0, 0.0, 1.0);
	col += glow_color * pow(max(sd, 0.0), 5.0) * glow_amt * (0.35 + 0.65 * hz);
	col += glow_color * pow(max(sd, 0.0), 80.0) * glow_amt * 1.5;
	float cm = 0.0;
	if (y > 0.0 && clouds > 0.0) {
		vec2 uv = d.xz / (y + 0.06) * 0.9 + vec2(TIME * 0.003, TIME * 0.001);
		float cn = fbm(uv * 1.3);
		cm = smoothstep(0.62 - clouds * 0.25, 0.9 - clouds * 0.25, cn) * smoothstep(0.0, 0.1, y);
		float shade = clamp(fbm(uv * 1.3 + vec2(0.25, 0.15)) * 1.6 - 0.35 + pow(max(sd, 0.0), 3.0) * 0.6, 0.0, 1.0);
		col = mix(col, mix(cloud_dark, cloud_lit, shade), cm * 0.92);
	}
	if (stars > 0.0 && y > 0.0) {
		vec2 stc = vec2(atan(d.x, d.z), asin(y)) * 320.0;
		vec2 cell = floor(stc);
		vec2 f = fract(stc) - 0.5;
		float h = hash(cell);
		float s = step(0.994, h) * smoothstep(0.4, 0.0, length(f)) * (0.55 + 0.45 * sin(TIME * 2.0 + h * 120.0));
		col += vec3(s) * stars * smoothstep(0.0, 0.2, y) * 1.5;
	}
	float disk = smoothstep(sun_size, sun_size + 0.00015, sd);
	col = mix(col, sun_color * sun_energy, disk * (1.0 - cm));
	COLOR = col;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 deep : source_color;
uniform vec3 far_col : source_color;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float swell = 0.5;
uniform float chop = 1.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float p1 = wp.x * 0.021 + wp.z * 0.013 + TIME * 0.7;
	float p2 = wp.z * 0.034 - wp.x * 0.008 + TIME * 1.1;
	float p3 = (wp.x + wp.z) * 0.06 + TIME * 1.7;
	VERTEX.y += (sin(p1) * 0.7 + sin(p2) * 0.45 + sin(p3) * 0.18) * swell;
	float dx = cos(p1) * 0.7 * 0.021 + cos(p2) * 0.45 * -0.008 + cos(p3) * 0.18 * 0.06;
	float dz = cos(p1) * 0.7 * 0.013 + cos(p2) * 0.45 * 0.034 + cos(p3) * 0.18 * 0.06;
	NORMAL = normalize(vec3(-dx * swell, 1.0, -dz * swell));
}
void fragment() {
	vec2 uv = wp.xz;
	vec3 a = texture(n1, uv * 0.018 + vec2(TIME * 0.012, TIME * 0.007)).rgb * 2.0 - 1.0;
	vec3 b = texture(n2, uv * 0.047 + vec2(-TIME * 0.009, TIME * 0.014)).rgb * 2.0 - 1.0;
	vec3 c = texture(n1, uv * 0.0045 + vec2(TIME * 0.003, -TIME * 0.002)).rgb * 2.0 - 1.0;
	vec3 nm = normalize(vec3((a.xy + b.xy * 0.7) * chop + c.xy * 0.9, 1.0));
	float dist = length(wp - CAMERA_POSITION_WORLD);
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(1.2, 0.3, clamp(dist / 2500.0, 0.0, 1.0));
	ALBEDO = mix(deep, far_col, clamp(dist / 3500.0, 0.0, 1.0) * 0.7);
	ROUGHNESS = 0.1;
	SPECULAR = 0.4;
	METALLIC = 0.0;
}
"""

const WAKE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;
uniform sampler2D foam : filter_linear_mipmap, repeat_enable;
uniform float brightness = 1.0;
void fragment() {
	float ax = abs(UV.x * 2.0 - 1.0);
	float center = smoothstep(0.55, 0.0, ax);
	float edge = smoothstep(0.08, 0.0, abs(ax - 0.9)) * 0.35;
	float n = texture(foam, vec2(UV.x * 2.5, UV.y * 14.0 + TIME * 0.03)).r;
	float fade = 1.0 - UV.y;
	float a = (center * fade * fade * fade + edge * fade * fade) * smoothstep(0.4, 0.75, n + fade * 0.25);
	ALBEDO = vec3(0.9, 0.94, 1.0) * brightness;
	ROUGHNESS = 0.85;
	ALPHA = clamp(a, 0.0, 0.7);
}
"""

const DECK_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D marks : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float tint = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 m = texture(marks, UV).rgb;
	float g = texture(grain, lp.xz * 0.35).r;
	float g2 = texture(grain, lp.xz * 0.018).r;
	ALBEDO = m * (0.82 + 0.3 * g) * (0.88 + 0.24 * g2) * tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
"""

##############################################################################
## SCENE CONSTRUCTION
##############################################################################

func _noise_tex(freq: float, normal_map: bool, size: int = 512, ramp: Gradient = null) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = fn
	if normal_map:
		t.as_normal_map = true
		t.bump_strength = 6.0
	if ramp:
		t.color_ramp = ramp
	return t

func _grime_mat(col: Color, rough: float, scale: float = 0.06) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	var g := Gradient.new()
	g.set_color(0, Color(0.78, 0.78, 0.78))
	g.set_color(1, Color(1.0, 1.0, 1.0))
	m.albedo_texture = _noise_tex(0.02, false, 256, g)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m

func _plain_mat(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _emit_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _build_scene() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	var root3 := Node3D.new()
	vp.add_child(root3)

	# Environment
	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 800.0
	root3.add_child(sun)

	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.near = 0.5
	cam.far = 9000.0
	cam.current = true
	root3.add_child(cam)

	# Ocean
	water_mat = ShaderMaterial.new()
	var wsh := Shader.new()
	wsh.code = WATER_SHADER
	water_mat.shader = wsh
	water_mat.set_shader_parameter("n1", _noise_tex(0.012, true, 512))
	water_mat.set_shader_parameter("n2", _noise_tex(0.03, true, 512))
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	pm.subdivide_width = 140
	pm.subdivide_depth = 140
	ocean = MeshInstance3D.new()
	ocean.mesh = pm
	ocean.material_override = water_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(ocean)

	# Wake (stays put; the carrier's heave doesn't move it)
	wake_mat = ShaderMaterial.new()
	var wk := Shader.new()
	wk.code = WAKE_SHADER
	wake_mat.shader = wk
	wake_mat.set_shader_parameter("foam", _noise_tex(0.05, false, 256))
	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w0 := _ship_to_land(-13, 2)
	var w1 := _ship_to_land(15, 2)
	var w2 := _ship_to_land(38, -450)
	var w3 := _ship_to_land(-36, -450)
	_quad(ws, _g(w0, 0.9), _g(w1, 0.9), _g(w2, 0.9), _g(w3, 0.9), Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var wake := MeshInstance3D.new()
	wake.mesh = ws.commit()
	wake.material_override = wake_mat
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(wake)

	carrier = Node3D.new()
	root3.add_child(carrier)
	_build_carrier()

##############################################################################
## MESH HELPERS  (landing coords (x, z) -> Godot (x, y, -z))
##############################################################################

func _g(v: Vector2, y: float) -> Vector3:
	return Vector3(v.x, y, -v.y)

func _tri(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	# Godot front faces are clockwise; keep winding consistent with the normal
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	s.set_normal(n)
	s.set_uv(ua)
	s.add_vertex(a)
	s.set_normal(n)
	s.set_uv(ub)
	s.add_vertex(b)
	s.set_normal(n)
	s.set_uv(uc)
	s.add_vertex(c)

func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
	_tri(s, a, b, c, n, ua, ub, uc)
	_tri(s, a, c, d, n, ua, uc, ud)

func _outward(o: PackedVector2Array, i: int) -> Vector2:
	var area := 0.0
	for k in range(o.size()):
		area += o[k].x * o[(k + 1) % o.size()].y - o[(k + 1) % o.size()].x * o[k].y
	var sgn := 1.0 if area > 0.0 else -1.0
	var e := o[(i + 1) % o.size()] - o[i]
	return Vector2(e.y, -e.x).normalized() * sgn

func _prism(s: SurfaceTool, o: PackedVector2Array, y0: float, y1: float, top: bool, bottom: bool, uv_fn: Callable = Callable()) -> void:
	for i in range(o.size()):
		var a := o[i]
		var b := o[(i + 1) % o.size()]
		var n2 := _outward(o, i)
		var n := Vector3(n2.x, 0, -n2.y)
		var ln := a.distance_to(b)
		_quad(s, _g(a, y1), _g(b, y1), _g(b, y0), _g(a, y0), n, Vector2(0, 0), Vector2(ln * 0.05, 0), Vector2(ln * 0.05, (y1 - y0) * 0.05), Vector2(0, (y1 - y0) * 0.05))
	if top or bottom:
		var idx := Geometry2D.triangulate_polygon(o)
		for k in range(0, idx.size(), 3):
			var pa := o[idx[k]]
			var pb := o[idx[k + 1]]
			var pc := o[idx[k + 2]]
			var ua := Vector2.ZERO
			var ub := Vector2.ZERO
			var uc := Vector2.ZERO
			if uv_fn.is_valid():
				ua = uv_fn.call(pa)
				ub = uv_fn.call(pb)
				uc = uv_fn.call(pc)
			if top:
				_tri(s, _g(pa, y1), _g(pb, y1), _g(pc, y1), Vector3.UP, ua, ub, uc)
			if bottom:
				_tri(s, _g(pa, y0), _g(pb, y0), _g(pc, y0), Vector3.DOWN, ua, ub, uc)

func _edge_quad(s: SurfaceTool, o: PackedVector2Array, i: int, t0: float, t1: float, y0: float, y1: float, out: float = 0.12) -> void:
	var a := o[i]
	var b := o[(i + 1) % o.size()]
	var n2 := _outward(o, i)
	var p0 := a.lerp(b, t0) + n2 * out
	var p1 := a.lerp(b, t1) + n2 * out
	_quad(s, _g(p0, y1), _g(p1, y1), _g(p1, y0), _g(p0, y0), Vector3(n2.x, 0, -n2.y))

func _add_mesh(s: SurfaceTool, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = s.commit()
	mi.material_override = mat
	(parent if parent else carrier).add_child(mi)
	return mi

func _st() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	return s

##############################################################################
## CARRIER
##############################################################################

func _deck_uv(p: Vector2) -> Vector2:
	return Vector2((p.x - deck_bb.position.x) / deck_bb.size.x, (deck_bb.end.y - p.y) / deck_bb.size.y)

func _build_carrier() -> void:
	var dh := DECK_H
	# Hull: red anti-fouling below the waterline, haze gray above, dark gallery band
	var s := _st()
	_prism(s, hull_l, -10.0, 1.2, false, false)
	_add_mesh(s, _plain_mat(Color(0.36, 0.09, 0.08), 0.7))
	s = _st()
	_prism(s, hull_l, 1.2, dh - 5.5, false, false)
	_add_mesh(s, _grime_mat(Color(0.27, 0.30, 0.34), 0.75))
	s = _st()
	_prism(s, hull_l, dh - 5.5, dh - 2.5, false, true)
	_add_mesh(s, _plain_mat(Color(0.14, 0.15, 0.17), 0.8))
	# Deck slab (edge + underside of the overhang)
	s = _st()
	_prism(s, deck_l, dh - 2.5, dh - 0.02, false, true)
	_add_mesh(s, _grime_mat(Color(0.22, 0.24, 0.27), 0.8))
	# Hangar bay openings, portholes, stern gallery
	var dark := _plain_mat(Color(0.02, 0.025, 0.03), 0.4)
	win_mat = _plain_mat(Color(0.03, 0.04, 0.05), 0.15, 0.2)
	s = _st()
	_edge_quad(s, hull_l, 6, 0.30, 0.42, 7.0, 12.5)
	_edge_quad(s, hull_l, 6, 0.58, 0.66, 7.0, 12.5)
	_edge_quad(s, hull_l, 2, 0.46, 0.56, 7.0, 12.5)
	_edge_quad(s, hull_l, 0, 0.44, 0.56, 4.0, 11.0)
	_add_mesh(s, dark)
	s = _st()
	for k in range(16):
		var t := 0.07 + k * 0.056
		_edge_quad(s, hull_l, 6, t, t + 0.008, 4.2, 5.0)
		_edge_quad(s, hull_l, 2, t, t + 0.008, 4.2, 5.0)
	_edge_quad(s, hull_l, 0, 0.12, 0.88, dh - 9.5, dh - 8.2)
	_add_mesh(s, win_mat)
	# Deck top with painted markings
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in deck_l:
		mn = mn.min(p)
		mx = mx.max(p)
	deck_bb = Rect2(mn, mx - mn)
	s = _st()
	_prism(s, deck_l, dh - 0.05, dh, true, false, _deck_uv)
	var dm := ShaderMaterial.new()
	var dsh := Shader.new()
	dsh.code = DECK_SHADER
	dm.shader = dsh
	dm.set_shader_parameter("marks", _paint_deck())
	dm.set_shader_parameter("grain", _noise_tex(0.08, false, 256))
	_add_mesh(s, dm)
	# Wires (slightly raised cables)
	s = _st()
	for wz in WIRE_Z:
		_prism(s, PackedVector2Array([Vector2(-13, wz - 0.12), Vector2(13, wz - 0.12), Vector2(13, wz + 0.12), Vector2(-13, wz + 0.12)]), dh, dh + 0.18, true, false)
	_add_mesh(s, _plain_mat(Color(0.55, 0.55, 0.52), 0.35, 0.8))
	# Catapult blast deflectors (raised panels)
	s = _st()
	for cx in [-5.0, 9.0]:
		_prism(s, _ship_rect(cx - 4.0, cx + 4.0, 240.0, 241.0), dh, dh + 0.4, true, false)
	_add_mesh(s, _plain_mat(Color(0.25, 0.27, 0.3), 0.6))
	_build_island(dh)
	_build_jets(dh)
	_build_lights(dh)

func _build_island(dh: float) -> void:
	var s := _st()
	for bi in range(3):
		var b: Array = island_l[bi]
		_prism(s, b[0], dh + float(b[1]), dh + float(b[2]), true, false)
	_add_mesh(s, _grime_mat(Color(0.44, 0.47, 0.51), 0.7, 0.1))
	s = _st()
	var stack: Array = island_l[3]
	_prism(s, stack[0], dh + float(stack[1]), dh + float(stack[2]), true, false)
	_add_mesh(s, _plain_mat(Color(0.1, 0.1, 0.11), 0.8))
	# Window bands on all four faces of each tier
	s = _st()
	var rows := [[17.5, 20.0], [23.0, 27.0], [30.0, 32.0]]
	for bi in range(3):
		var o: PackedVector2Array = island_l[bi][0]
		for ei in range(4):
			_edge_quad(s, o, ei, 0.06, 0.94, dh + rows[bi][0], dh + rows[bi][1], 0.1)
	_add_mesh(s, win_mat)
	# Mast, yardarms, radar, dish, antennas
	var mb := _ship_to_land(28.5, 180.0)
	var metal := _plain_mat(Color(0.7, 0.72, 0.75), 0.4, 0.4)
	var mast := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.5
	cyl.height = 20.0
	mast.mesh = cyl
	mast.material_override = metal
	mast.position = _g(mb, dh + 34.0 + 10.0)
	carrier.add_child(mast)
	var yaw := -deg_to_rad(DECK_ANGLE)
	for yy in [[44.0, 9.0], [50.0, 6.0]]:
		var ya := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(yy[1], 0.25, 0.25)
		ya.mesh = bm
		ya.material_override = metal
		ya.position = _g(mb, dh + yy[0])
		ya.rotation.y = yaw
		carrier.add_child(ya)
	radar = MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(6.5, 1.3, 0.35)
	radar.mesh = rm
	radar.material_override = metal
	radar.position = _g(mb, dh + 39.5)
	carrier.add_child(radar)
	var dish := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 1.2
	dish.mesh = sm
	dish.material_override = _plain_mat(Color(0.85, 0.87, 0.9), 0.5)
	dish.position = _g(_ship_to_land(27.5, 196.0), dh + 34.6)
	carrier.add_child(dish)
	for ax in [[26.5, 172.0, 34.0, 7.0], [30.5, 190.0, 38.5, 5.0], [31.0, 166.0, 28.0, 6.0]]:
		var an := MeshInstance3D.new()
		var ac := CylinderMesh.new()
		ac.top_radius = 0.06
		ac.bottom_radius = 0.1
		ac.height = ax[3]
		an.mesh = ac
		an.material_override = metal
		an.position = _g(_ship_to_land(ax[0], ax[1]), dh + ax[2] + ax[3] * 0.5)
		carrier.add_child(an)
	beacon = MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.35
	bsm.height = 0.7
	beacon.mesh = bsm
	beacon.material_override = _emit_mat(Color(1, 0.15, 0.1), 8.0)
	beacon.position = _g(mb, dh + 54.3)
	carrier.add_child(beacon)

func _loft(st: SurfaceTool, sections: Array, n: int) -> void:
	# sections: [z, half_width, half_height, y_center] from nose to tail
	var rings := []
	for sec in sections:
		var ring := []
		for i in range(n):
			var a := TAU * i / n
			ring.append(Vector3(cos(a) * sec[1], sec[3] + sin(a) * sec[2], -sec[0]))
		rings.append(ring)
	for r in range(rings.size() - 1):
		var r0: Array = rings[r]
		var r1: Array = rings[r + 1]
		var c0 := Vector3(0, sections[r][3], -sections[r][0])
		var c1 := Vector3(0, sections[r + 1][3], -sections[r + 1][0])
		for i in range(n):
			var j := (i + 1) % n
			var mid: Vector3 = (r0[i] + r0[j] + r1[i] + r1[j]) * 0.25
			var nrm: Vector3 = (mid - (c0 + c1) * 0.5).normalized()
			_quad(st, r0[i], r0[j], r1[j], r1[i], nrm)
	# tail cap
	var last: Array = rings[rings.size() - 1]
	var lc := Vector3(0, sections[sections.size() - 1][3], -sections[sections.size() - 1][0])
	for i in range(n):
		_tri(st, lc, last[i], last[(i + 1) % n], Vector3(0, 0, 1))

func _fin(st: SurfaceTool, side: float) -> void:
	# Canted twin tail fin (two faces so it has thickness)
	var base_x := 1.35 * side
	var top_x := 2.05 * side
	var pts := [Vector3(base_x, 2.2, 4.4), Vector3(base_x, 2.2, 8.3), Vector3(top_x, 5.7, 8.5), Vector3(top_x, 5.7, 6.6)]
	var nrm := Vector3(0.98 * side, -0.2, 0).normalized()
	var off := nrm * 0.07
	_quad(st, pts[0] + off, pts[1] + off, pts[2] + off, pts[3] + off, nrm)
	_quad(st, pts[0] - off, pts[1] - off, pts[2] - off, pts[3] - off, -nrm)
	_quad(st, pts[3] + off, pts[2] + off, pts[2] - off, pts[3] - off, Vector3.UP)

func _build_jets(dh: float) -> void:
	# Low-poly F-14 style jet, parked with wings swept fully back
	var body := _st()
	var dark := _st()
	_loft(body, [
		[9.9, 0.03, 0.03, 1.75],
		[9.0, 0.34, 0.34, 1.75],
		[7.4, 0.62, 0.58, 1.78],
		[5.2, 0.85, 0.72, 1.82],
		[3.2, 1.55, 0.72, 1.72],
		[1.0, 2.20, 0.70, 1.62],
		[-3.0, 2.35, 0.66, 1.58],
		[-6.4, 2.05, 0.60, 1.52],
		[-8.3, 1.55, 0.50, 1.50],
	], 14)
	for sg in [1.0, -1.0]:
		# swept wing (Tomcat parked at full sweep)
		_prism(body, PackedVector2Array([Vector2(1.9 * sg, 2.6), Vector2(6.3 * sg, -5.4), Vector2(6.1 * sg, -6.4), Vector2(1.9 * sg, -2.2)]), 1.55, 1.8, true, true)
		# wing glove
		_prism(body, PackedVector2Array([Vector2(1.9 * sg, 4.8), Vector2(2.9 * sg, 1.2), Vector2(1.9 * sg, 0.6)]), 1.6, 1.85, true, true)
		# horizontal stabilizer
		_prism(body, PackedVector2Array([Vector2(1.7 * sg, -5.2), Vector2(5.3 * sg, -7.7), Vector2(5.3 * sg, -8.4), Vector2(1.7 * sg, -8.0)]), 1.42, 1.56, true, true)
		_fin(body, sg)
	# engine nozzle (one mesh, placed twice)
	_loft(dark, [[-8.0, 0.62, 0.62, 1.45], [-8.9, 0.55, 0.55, 1.45]], 10)
	var body_mesh := body.commit()
	var dark_mesh := dark.commit()
	var jm := _plain_mat(Color(0.56, 0.59, 0.63), 0.5, 0.15)
	var dm := _plain_mat(Color(0.12, 0.12, 0.13), 0.6, 0.5)
	var gm := _plain_mat(Color(0.04, 0.07, 0.11), 0.08, 0.4)
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 0.55
	canopy_mesh.height = 1.0
	for j in PARKED:
		var root := Node3D.new()
		var lp := _ship_to_land(j[0], j[1])
		root.position = _g(lp, dh)
		root.rotation.y = -deg_to_rad(DECK_ANGLE + 28.0)
		var b := MeshInstance3D.new()
		b.mesh = body_mesh
		b.material_override = jm
		root.add_child(b)
		for sx in [1.1, -1.1]:
			var nz := MeshInstance3D.new()
			nz.mesh = dark_mesh
			nz.material_override = dm
			nz.position = Vector3(sx, 0, 0)
			root.add_child(nz)
		var cp := MeshInstance3D.new()
		cp.mesh = canopy_mesh
		cp.material_override = gm
		cp.position = Vector3(0, 2.45, -4.9)
		cp.scale = Vector3(1.0, 0.85, 2.3)
		root.add_child(cp)
		carrier.add_child(root)

func _light_dot(pos: Vector3, col: Color, r: float, energy: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = _emit_mat(col, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	night_lights.add_child(mi)

func _build_lights(dh: float) -> void:
	night_lights = Node3D.new()
	carrier.add_child(night_lights)
	for i in range(15):
		var z := 4.0 + i * 15.0
		_light_dot(_g(Vector2(-LANE_HALF - 0.5, z), dh + 0.2), Color(1, 0.95, 0.85), 0.28, 6.0)
		_light_dot(_g(Vector2(LANE_HALF + 0.5, z), dh + 0.2), Color(1, 0.95, 0.85), 0.28, 6.0)
		_light_dot(_g(Vector2(0, z + 6.0), dh + 0.12), Color(0.85, 0.9, 1.0), 0.2, 4.0)
	for i in range(7):
		_light_dot(_g(Vector2(0, -0.6), dh - 1.8 - i * 2.4), Color(1, 0.55, 0.1), 0.35, 7.0)
	for p in deck_l:
		_light_dot(_g(p, dh + 0.3), Color(1, 0.2, 0.15), 0.3, 6.0)

##############################################################################
## DECK MARKINGS TEXTURE (painted once at startup)
##############################################################################

func _dpx(x: float, z: float) -> Vector2i:
	return Vector2i(int((x - deck_bb.position.x) * PPM), int((deck_bb.end.y - z) * PPM))

func _paint_rect(img: Image, x0: float, x1: float, z0: float, z1: float, col: Color) -> void:
	var a := _dpx(x0, z1)
	var b := _dpx(x1, z0)
	var r := Rect2i(a, Vector2i(maxi(b.x - a.x, 1), maxi(b.y - a.y, 1)))
	img.fill_rect(r.intersection(Rect2i(0, 0, img.get_width(), img.get_height())), col)

func _paint_poly(img: Image, poly: PackedVector2Array, col: Color) -> void:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in poly:
		mn = mn.min(p)
		mx = mx.max(p)
	var a := _dpx(mn.x, mx.y)
	var b := _dpx(mx.x, mn.y)
	for py in range(maxi(a.y, 0), mini(b.y + 1, img.get_height())):
		for pxx in range(maxi(a.x, 0), mini(b.x + 1, img.get_width())):
			var w := Vector2(deck_bb.position.x + (pxx + 0.5) / PPM, deck_bb.end.y - (py + 0.5) / PPM)
			if Geometry2D.is_point_in_polygon(w, poly):
				img.set_pixel(pxx, py, col)

func _paint_line_ship(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var la := _ship_to_land(a.x, a.y)
	var lb := _ship_to_land(b.x, b.y)
	var steps := int(la.distance_to(lb) * PPM) + 1
	var r := maxi(int(w * PPM * 0.5), 1)
	for k in range(steps + 1):
		var p := la.lerp(lb, float(k) / steps)
		var q := _dpx(p.x, p.y)
		img.fill_rect(Rect2i(q.x - r, q.y - r, r * 2, r * 2).intersection(Rect2i(0, 0, img.get_width(), img.get_height())), col)

func _paint_deck() -> ImageTexture:
	var w := int(deck_bb.size.x * PPM) + 1
	var h := int(deck_bb.size.y * PPM) + 1
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var base := Color(0.40, 0.41, 0.43)
	var lane := Color(0.31, 0.32, 0.34)
	var white := Color(0.92, 0.92, 0.88)
	var yellow := Color(0.95, 0.75, 0.15)
	var red := Color(0.75, 0.12, 0.1)
	img.fill(base)
	# Deck edge line
	for i in range(DECK_OUTLINE.size()):
		var a: Vector2 = DECK_OUTLINE[i]
		var b: Vector2 = DECK_OUTLINE[(i + 1) % DECK_OUTLINE.size()]
		var n := (b - a).orthogonal().normalized()
		_paint_line_ship(img, a + n * 1.2, b + n * 1.2, 0.5, white)
	# Landing area, seams, tire rubber
	_paint_rect(img, -13.5, 13.5, 0.0, LANE_LEN, lane)
	var zz := 18.0
	while zz < LANE_LEN:
		_paint_rect(img, -13.5, 13.5, zz, zz + 0.25, lane.darkened(0.12))
		zz += 18.0
	for tm in TIRE_MARKS:
		_paint_rect(img, tm[0] - 0.35, tm[0] + 0.35, tm[1], tm[1] + tm[2], Color(0.2, 0.2, 0.21))
		_paint_rect(img, tm[0] + 1.6, tm[0] + 2.0, tm[1] + 3.0, tm[1] + tm[2] * 0.7, Color(0.24, 0.24, 0.25))
	# Lane edges, centerline, ramp, foul line
	for i in range(20):
		var z0 := 8.0 + i * 10.5
		_paint_rect(img, -LANE_HALF - 0.45, -LANE_HALF + 0.45, z0, z0 + 6.0, white)
		_paint_rect(img, LANE_HALF - 0.45, LANE_HALF + 0.45, z0, z0 + 6.0, white)
		_paint_rect(img, -0.4, 0.4, z0 + 2.0, z0 + 7.0, white)
	for i in range(13):
		_paint_rect(img, -13.0 + i * 2.0, -11.0 + i * 2.0, 0.2, 1.4, red if i % 2 == 0 else white)
	_paint_rect(img, -13.5, 13.5, 3.0, 3.5, yellow)
	for wz in WIRE_Z:
		_paint_rect(img, -14.2, -13.0, wz - 0.8, wz + 0.8, Color(0.2, 0.21, 0.23))
		_paint_rect(img, 13.0, 14.2, wz - 0.8, wz + 0.8, Color(0.2, 0.21, 0.23))
	# Elevators, catapults, safety lines
	for e in [[12.0, 24.0, 108.0, 128.0], [24.0, 34.0, 212.0, 224.0], [-22.0, -12.0, 140.0, 156.0]]:
		_paint_poly(img, _ship_rect(e[0], e[1], e[2], e[3]), base.darkened(0.08))
		for edge in [[e[0], e[2], e[1], e[2]], [e[1], e[2], e[1], e[3]], [e[1], e[3], e[0], e[3]], [e[0], e[3], e[0], e[2]]]:
			_paint_line_ship(img, Vector2(edge[0], edge[1]), Vector2(edge[2], edge[3]), 0.3, yellow)
	for cx in [-5.0, 9.0]:
		_paint_line_ship(img, Vector2(cx, 252), Vector2(cx, 324), 0.6, Color(0.62, 0.63, 0.64))
		_paint_line_ship(img, Vector2(cx - 1.5, 250), Vector2(cx - 1.5, 326), 0.25, white)
		_paint_line_ship(img, Vector2(cx + 1.5, 250), Vector2(cx + 1.5, 326), 0.25, white)
	_paint_line_ship(img, Vector2(20, 20), Vector2(20, 140), 0.3, yellow)
	_paint_line_ship(img, Vector2(20, 235), Vector2(18, 295), 0.3, yellow)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

##############################################################################
## PER-LEVEL LOOK
##############################################################################

func _apply_level() -> void:
	if not env:
		return
	for k in ["zenith", "horizon", "below", "glow", "cloud_lit", "cloud_dark"]:
		var pname: String = {"glow": "glow_color"}.get(k, k)
		sky_mat.set_shader_parameter(pname, pal[k])
	sky_mat.set_shader_parameter("sun_color", pal["sun_col"])
	sky_mat.set_shader_parameter("sun_energy", pal["sun_energy"])
	sky_mat.set_shader_parameter("sun_size", pal["sun_size"])
	sky_mat.set_shader_parameter("glow_amt", pal["glow_amt"])
	sky_mat.set_shader_parameter("stars", pal["stars"])
	sky_mat.set_shader_parameter("clouds", pal["clouds"])
	sun.rotation_degrees = pal["sun_rot"]
	sun.light_color = pal["light_col"]
	sun.light_energy = pal["light_energy"]
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = pal["ambient"]
	env.fog_light_color = pal["fog"]
	env.fog_density = pal["fog_density"]
	env.tonemap_exposure = pal["exposure"]
	water_mat.set_shader_parameter("deep", pal["water"])
	water_mat.set_shader_parameter("far_col", pal["water_far"])
	water_mat.set_shader_parameter("swell", pal["swell"])
	water_mat.set_shader_parameter("chop", pal["chop"])
	wake_mat.set_shader_parameter("brightness", 0.35 if pal["night"] else 1.0)
	night_lights.visible = pal["night"]
	if pal["night"]:
		win_mat.emission_enabled = true
		win_mat.emission = Color(1.0, 0.72, 0.38)
		win_mat.emission_energy_multiplier = 0.55
	else:
		win_mat.emission_enabled = false

func _update_frame() -> void:
	if not cam:
		return
	var bank := _bank()
	cam.position = Vector3(px, _eye_y(), dist)
	cam.rotation = Vector3(deg_to_rad(CAM_PITCH + pitch_px * 0.35 - jolt * 0.35), 0.0, -bank)
	if shake > 0.0:
		cam.h_offset = randf_range(-1, 1) * shake * 0.25
		cam.v_offset = randf_range(-1, 1) * shake * 0.2
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	carrier.position.y = _heave()
	ocean.position = Vector3(snappedf(px, 60.0), 0.0, snappedf(dist, 60.0))
	radar.rotation.y = tt * 2.5
	beacon.visible = fmod(tt, 1.0) < 0.5
	overlay.queue_redraw()

func _bank() -> float:
	if st == St.RESULT or st == St.DONE or (st == St.TOUCHDOWN and result != "splash"):
		return 0.0
	return roll * 0.6

func _eye_y() -> float:
	var target := td_zc if hook_down else WIRE_Z[2]
	var d := maxf(target + dist, 0.0)
	var alt := DECK_H + _heave() + EYE_TD + d * GLIDE
	if st == St.TOUCHDOWN and result != "crash" and result != "splash":
		alt = DECK_H + _heave() + EYE_TD
	return alt + extra_alt
func _on_left_on(_m = null) -> void: sw_left = true
func _on_left_off(_m = null) -> void: sw_left = false
func _on_right_on(_m = null) -> void: sw_right = true
func _on_right_off(_m = null) -> void: sw_right = false

func _on_begin(m = null) -> void:
	if st != St.WAIT:
		return
	var lv := _machine_level()
	if m is Dictionary and m.has("level"):
		var v = m["level"]
		if v is int or v is float:
			lv = int(v)
		elif v is String and v.is_valid_int():
			lv = v.to_int()
	_start(lv)

func _machine_level() -> int:
	if MPF.game and MPF.game.machine_vars.has("landing_level"):
		return int(MPF.game.machine_vars["landing_level"])
	return 1

func _set_level(lv: int) -> void:
	level = clampi(lv, 1, 3)
	cfg = LEVELS[level]
	pal = PAL[level]
	spd = float(cfg["speed"])
	# Window opens when the jet is HOOK_WINDOW seconds from the 3-wire
	d_window = spd * HOOK_WINDOW - WIRE_Z[2]
	d0 = d_window + spd * float(cfg["app_time"])
	move_spd = spd
	_apply_level()

func _start(lv: int) -> void:
	_set_level(lv)
	dist = d0
	var off := float(cfg["start_off"])
	px = (off + randf() * 4.0) * (1.0 if randf() < 0.5 else -1.0)
	pv = 0.0
	roll = 0.0
	voice_called = false
	move_spd = spd
	# Crosswind holds one direction for the whole approach
	wind_dir = 1.0 if randf() < 0.5 else -1.0
	gust = 0.0
	gust_target = 0.0
	_go(St.INTRO)

func _go(s: int) -> void:
	st = s
	st_t = 0.0

func _ev(e: String) -> void:
	MPF.server.send_event(e)

##############################################################################

##############################################################################
## SIMULATION
##############################################################################

func _ball() -> float:
	var a2 := 0.0
	var b := sin(TAU * tt / float(cfg["p1"])) + a2 * sin(TAU * tt / float(cfg["p2"]) + 1.7)
	return b / (1.0 + a2 * 0.6)

func _heave() -> float:
	return -_ball() * HEAVE_M

func _progress() -> float:
	return clampf(1.0 - dist / d0, 0.0, 1.0)

func _input_dir() -> float:
	var l := sw_left or Input.is_physical_key_pressed(KEY_LEFT)
	var r := sw_right or Input.is_physical_key_pressed(KEY_RIGHT)
	if l and not r:
		return -1.0
	if r and not l:
		return 1.0
	return 0.0

func _both_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_SPACE):
		return true
	return sw_left and sw_right

func _update_wind(dt: float) -> void:
	# Steady crosswind from one side; gusts only make it stronger (same side)
	var base := float(cfg["wind"]) * (0.92 + 0.08 * sin(0.35 * tt + wind_p1))
	var g := float(cfg["gust"])
	if g > 0.0:
		gust_t -= dt
		if gust_t <= 0.0:
			gust_t = randf_range(2.0, 4.0)
			gust_target = randf_range(0.4, 1.0) * g if gust_target <= 0.01 else 0.0
		gust = move_toward(gust, gust_target, g * 0.6 * dt)
	wind = wind_dir * (base + gust)

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	tt += dt
	st_t += dt
	shake = maxf(0.0, shake - dt * 1.8)
	flash = maxf(0.0, flash - dt * 1.5)
	jolt = move_toward(jolt, 0.0, dt * 30.0)
	_update_particles(dt)
	_update_water(dt)

	match st:
		St.WAIT:
			if st_t >= WAIT_FALLBACK:
				_start(_machine_level())
		St.INTRO:
			if st_t >= INTRO_TIME:
				_go(St.APPROACH)
				_ev("landing_sfx_engine_start")
		St.APPROACH, St.WINDOW:
			_fly(dt, true)
			if st == St.APPROACH and not voice_called and dist <= d_window + spd * CALL_BALL_LEAD:
				voice_called = true
				_ev("landing_sfx_call_ball_voice")
			if st == St.APPROACH and dist <= d_window:
				_go(St.WINDOW)
				_ev("landing_sfx_call_ball")
			elif st == St.WINDOW:
				if _both_pressed():
					_commit()
				elif dist <= -WIRE_Z[2] and not _on_deck(px, WIRE_Z[2]):
					_resolve_splash()
				elif dist <= -WIRE_Z[2] and absf(px) > X_CRASH:
					crash_reason = "CRASHED ON DECK - CHECK LINEUP"
					_resolve_crash()
				elif dist <= -WIRE_Z[2]:
					# 5 seconds are up and no hook -> missed the landing
					_resolve_bolter()
		St.COMMITTED:
			_fly(dt, false)
			if dist <= -td_zc:
				_touchdown()
		St.TOUCHDOWN:
			_touchdown_anim(dt)
		St.RESULT, St.DONE:
			if result == "bolter" or result == "waveoff":
				_climb_out(dt)
			if st == St.RESULT and st_t >= RESULT_TIME:
				_go(St.DONE)
				_ev("landing_done")
	_update_frame()

func _fly(dt: float, can_steer: bool) -> void:
	_update_wind(dt)
	var inp := _input_dir() if can_steer else 0.0
	roll = move_toward(roll, inp * MAX_BANK, ROLL_RATE * dt)
	pv += (BANK_ACC * roll / MAX_BANK - pv * DRIFT_DRAG) * dt
	px += (pv + wind) * dt
	dist -= move_spd * dt
	travelled += move_spd * dt
	if can_steer and absf(px) > LANE_HALF:
		warn_t -= dt
		if warn_t <= 0.0:
			warn_t = 0.8
			_ev("landing_sfx_warning")
	else:
		warn_t = 0.0

func _commit() -> void:
	hook_down = true
	_ev("landing_sfx_hook")
	var b := _ball()
	var r := ""
	if b < Z_CRASH:
		r = "crash"
		crash_reason = "HIT THE BACK OF THE CARRIER"
	elif b < Z_EARLY1:
		r = "wire_1"
	elif b < -Z_PERFECT:
		r = "wire_2"
	elif b <= Z_PERFECT:
		r = "wire_3"
	elif b <= Z_LATE:
		r = "wire_4"
	else:
		r = "bolter"
	result = r
	match r:
		"wire_1": td_zc = WIRE_Z[0]
		"wire_2": td_zc = WIRE_Z[1]
		"wire_3": td_zc = WIRE_Z[2]
		"wire_4": td_zc = WIRE_Z[3]
		"bolter": td_zc = WIRE_Z[3] + 8.0
		"crash": td_zc = -3.0 if crash_reason.begins_with("RAMP") else WIRE_Z[2]
	# Press = land: close the remaining distance quickly
	move_spd = maxf(spd, (dist + td_zc) / COMMIT_TIME)
	_go(St.COMMITTED)

func _on_deck(x: float, z: float) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(x, z), deck_l)

func _touchdown() -> void:
	# Not over the carrier at all -> into the water
	if not _on_deck(px, maxf(td_zc, 2.0)):
		_resolve_splash()
		return
	# Over the deck but outside the landing area lines -> crash
	if absf(px) > LANE_HALF and result != "crash" and result != "bolter":
		result = "crash"
		crash_reason = "MISSED THE LANDING AREA"
	match result:
		"wire_1", "wire_2", "wire_3", "wire_4":
			shake = 0.6
			jolt = 7.0
			_ev("landing_result_" + result)
			_ev("landing_sfx_trap")
			if result == "wire_3":
				_ev("landing_sfx_perfect")
			_go(St.TOUCHDOWN)
		"bolter":
			_resolve_bolter()
		"crash":
			_resolve_crash()

func _resolve_splash() -> void:
	result = "splash"
	crash_reason = ""
	splash_start_alt = _eye_y()
	_ev("landing_result_splash")
	_go(St.TOUCHDOWN)

func _splash_anim(dt: float) -> void:
	var fall := 1.0
	if st_t < fall:
		# Nose drops and the jet falls to the water
		var k := st_t / fall
		var base_eye := _eye_y() - extra_alt
		extra_alt = lerpf(splash_start_alt, 1.4, k * k) - base_eye
		pitch_px = lerpf(0.0, -22.0, k)
		dist -= spd * dt
		travelled += spd * dt
		return
	if splash_t < 0.0:
		splash_t = 0.0
		shake = 1.0
		flash = 0.7
		flash_col = Color(0.85, 0.95, 1.0)
		_ev("landing_sfx_splash")
		for i in range(110):
			var a := randf_range(PI * 1.05, PI * 1.95)
			var v := randf_range(250.0, 900.0)
			water_parts.append({"p": Vector2(640 + randf_range(-260, 260), 470), "v": Vector2(cos(a) * v * 0.6, sin(a) * v),
				"life": randf_range(0.7, 1.6), "max": 1.6, "r": randf_range(3.0, 14.0)})
	spd = maxf(0.0, spd - spd * 3.0 * dt)
	dist -= spd * dt
	splash_t += dt
	if st_t > fall + 2.4:
		_go(St.RESULT)

func _update_water(dt: float) -> void:
	for i in range(water_parts.size() - 1, -1, -1):
		var w: Dictionary = water_parts[i]
		w["life"] = float(w["life"]) - dt
		if float(w["life"]) <= 0.0:
			water_parts.remove_at(i)
			continue
		w["v"] = Vector2(w["v"]) + Vector2(0, 1400.0) * dt
		w["p"] = Vector2(w["p"]) + Vector2(w["v"]) * dt

func _touchdown_anim(dt: float) -> void:
	if result == "splash":
		_splash_anim(dt)
		return
	var decel := float(cfg["speed"]) / 1.3
	spd = maxf(0.0, spd - decel * dt)
	dist -= spd * dt
	travelled += spd * dt
	if result == "crash":
		if st_t > 2.2:
			_go(St.RESULT)
	elif spd <= 0.0 and st_t > 1.4:
		_go(St.RESULT)

func _resolve_bolter() -> void:
	result = "bolter"
	shake = 0.3
	jolt = 3.0
	_ev("landing_result_bolter")
	_ev("landing_sfx_bolter")
	_go(St.RESULT)

func _resolve_waveoff() -> void:
	result = "waveoff"
	_ev("landing_result_waveoff")
	_ev("landing_sfx_bolter")
	_go(St.RESULT)

func _climb_out(dt: float) -> void:
	extra_alt += (8.0 + st_t * 10.0) * dt
	pitch_px = move_toward(pitch_px, 34.0, dt * 22.0)
	dist -= spd * dt
	travelled += spd * dt

func _resolve_crash() -> void:
	result = "crash"
	shake = 1.0
	flash = 1.0
	fireball_t = 0.0
	var c := Vector2(LW * 0.5, 78)
	for i in range(80):
		var a := randf() * TAU
		var v := randf_range(20.0, 140.0)
		particles.append({"p": c, "v": Vector2(cos(a), sin(a) * 0.6 - 0.5) * v,
			"life": randf_range(0.6, 2.0), "max": 2.0, "s": randi_range(1, 3), "smoke": randf() < 0.35})
	cracks.clear()
	var o := Vector2(640 + randf_range(-120, 120), 250 + randf_range(-60, 40))
	for k in range(9):
		var ang := randf() * TAU
		var pts := PackedVector2Array([o])
		var p := o
		for seg in range(randi_range(3, 6)):
			ang += randf_range(-0.5, 0.5)
			p += Vector2(cos(ang), sin(ang)) * randf_range(25, 70)
			pts.append(p)
		cracks.append(pts)
	_ev("landing_result_crash")
	_ev("landing_sfx_crash")
	spd = spd * (0.03 if crash_reason.begins_with("RAMP") else 0.3)
	_go(St.TOUCHDOWN)

func _update_particles(dt: float) -> void:
	if fireball_t >= 0.0:
		fireball_t += dt
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p["life"] = float(p["life"]) - dt
		if float(p["life"]) <= 0.0:
			particles.remove_at(i)
			continue
		p["v"] = Vector2(p["v"]) * (1.0 - 1.4 * dt) + Vector2(0, 60.0 if not p["smoke"] else -18.0) * dt
		p["p"] = Vector2(p["p"]) + Vector2(p["v"]) * dt


##############################################################################
## COCKPIT / HUD OVERLAY  (drawn in 1280x720 space)
##############################################################################

const HUD_G := Color(0.45, 1.0, 0.55, 0.9)
var _font: Font

func _f() -> Font:
	if not _font:
		_font = ThemeDB.fallback_font
	return _font

func _text(o: CanvasItem, pos: Vector2, t: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, outline := 0) -> void:
	if outline > 0:
		o.draw_string_outline(_f(), pos, t, align, w, sz, outline, Color(0, 0, 0, col.a * 0.85))
	o.draw_string(_f(), pos, t, align, w, sz, col)

func _text_c(o: CanvasItem, cx: float, y: float, t: String, sz: int, col: Color, outline := 0) -> void:
	_text(o, Vector2(cx - 640, y), t, sz, col, HORIZONTAL_ALIGNMENT_CENTER, 1280, outline)

func _vgrad(o: CanvasItem, r: Rect2, c0: Color, c1: Color) -> void:
	o.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([c0, c0, c1, c1]))

func _rrect(o: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	o.draw_style_box(sb, r)

func _rrect_border(o: CanvasItem, r: Rect2, rad: float, col: Color, border: Color, bw: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	o.draw_style_box(sb, r)

func _comma(v: int) -> String:
	var s := str(v)
	var r := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			r += ","
		r += s[i]
	return r

func _draw_overlay(o: Control) -> void:
	var sc := o.size / Vector2(1280, 720)
	o.draw_set_transform(Vector2.ZERO, 0.0, sc)
	if st != St.RESULT and st != St.DONE and st != St.WAIT and st != St.INTRO and splash_t < 0.0:
		_hud(o)
	_explosion(o)
	_splash_fx(o)
	if flash > 0.0:
		o.draw_rect(Rect2(0, 0, 1280, 720), Color(flash_col.r, flash_col.g, flash_col.b, flash * 0.85))
	if result == "crash" and fireball_t > 0.8:
		o.draw_rect(Rect2(0, 0, 1280, 500), Color(0.45, 0.05, 0.0, clampf((fireball_t - 0.8) * 0.4, 0.0, 0.3)))
	for cr in cracks:
		o.draw_polyline(cr, Color(1, 1, 1, 0.55), 1.5, true)
		o.draw_polyline(cr, Color(1, 1, 1, 0.15), 4.0, true)
	_cockpit(o)
	match st:
		St.WAIT:
			_wait(o)
		St.INTRO:
			_intro(o)
		St.RESULT, St.DONE:
			_result_ui(o)
		_:
			_callouts(o)

# --- HUD symbology (collimated, rotates with bank) ---
func _hud(o: Control) -> void:
	var bank := _bank()
	var pitch := CAM_PITCH + pitch_px * 0.35 - jolt * 0.35
	var ctr := Vector2(640, 360)
	var hor_y := 360.0 + pitch * PX_PER_DEG
	var g := HUD_G
	var glow := Color(g.r, g.g, g.b, 0.18)
	o.draw_set_transform(ctr, bank, Vector2.ONE)
	var hy := hor_y - 360.0
	# Horizon line + pitch ladder
	for pass_i in range(2):
		var col := glow if pass_i == 0 else g
		var w := 4.0 if pass_i == 0 else 1.5
		o.draw_line(Vector2(-300, hy), Vector2(-70, hy), col, w, true)
		o.draw_line(Vector2(70, hy), Vector2(300, hy), col, w, true)
		for deg in [-10, -5]:
			var y: float = hy - deg * PX_PER_DEG
			if deg > 0:
				o.draw_line(Vector2(-150, y), Vector2(-70, y), col, w, true)
				o.draw_line(Vector2(70, y), Vector2(150, y), col, w, true)
				o.draw_line(Vector2(-150, y), Vector2(-150, y + 10), col, w, true)
				o.draw_line(Vector2(150, y), Vector2(150, y + 10), col, w, true)
			else:
				for k in range(4):
					o.draw_line(Vector2(-150 + k * 22, y), Vector2(-138 + k * 22, y), col, w, true)
					o.draw_line(Vector2(70 + k * 22, y), Vector2(82 + k * 22, y), col, w, true)
				o.draw_line(Vector2(-150, y), Vector2(-150, y - 10), col, w, true)
				o.draw_line(Vector2(150, y), Vector2(150, y - 10), col, w, true)
			if pass_i == 1:
				_text(o, Vector2(-190, y + 6), str(absi(deg)), 16, g)
				_text(o, Vector2(160, y + 6), str(absi(deg)), 16, g)
	o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Flight path marker (velocity vector)
	var fx := 640.0 + rad_to_deg(atan((pv + wind) / maxf(spd, 1.0))) * PX_PER_DEG
	var fy := hor_y + rad_to_deg(atan(GLIDE)) * PX_PER_DEG
	var fp := Vector2(fx, fy).rotated(0)
	for pass_i in range(2):
		var col2 := glow if pass_i == 0 else g
		var w2 := 4.0 if pass_i == 0 else 1.8
		o.draw_arc(fp, 9, 0, TAU, 32, col2, w2, true)
		o.draw_line(fp + Vector2(-30, 0), fp + Vector2(-9, 0), col2, w2, true)
		o.draw_line(fp + Vector2(9, 0), fp + Vector2(30, 0), col2, w2, true)
		o.draw_line(fp + Vector2(0, -9), fp + Vector2(0, -20), col2, w2, true)
	# AOA bracket beside the FPM
	o.draw_line(fp + Vector2(-44, -14), fp + Vector2(-44, 14), g, 1.5, true)
	o.draw_line(fp + Vector2(-44, -14), fp + Vector2(-38, -14), g, 1.5, true)
	o.draw_line(fp + Vector2(-44, 14), fp + Vector2(-38, 14), g, 1.5, true)
	o.draw_line(fp + Vector2(-44, 0), fp + Vector2(-40, 0), g, 1.5, true)
	# Heading tape
	var hdg := 270.0 + rad_to_deg(atan((pv + wind) / maxf(spd, 1.0)))
	var tape_y := 92.0
	o.draw_line(Vector2(520, tape_y), Vector2(760, tape_y), g, 1.5, true)
	for d in range(-30, 31, 5):
		var hv := int(round(hdg / 5.0) * 5) + d
		var x := 640.0 + (hv - hdg) * 8.0
		if x < 520 or x > 760:
			continue
		var big := hv % 10 == 0
		o.draw_line(Vector2(x, tape_y), Vector2(x, tape_y - (12 if big else 6)), g, 1.5, true)
		if big:
			_text(o, Vector2(x - 20, tape_y - 16), "%02d" % (posmod(hv, 360) / 10), 16, g, HORIZONTAL_ALIGNMENT_CENTER, 40)
	o.draw_colored_polygon(PackedVector2Array([Vector2(640, tape_y + 2), Vector2(634, tape_y + 12), Vector2(646, tape_y + 12)]), g)
	# Airspeed / altitude boxes
	var alt := maxi(int((_eye_y() - DECK_H) * 3.28), 0)
	for side in [[390.0, str(int(spd * 1.944))], [890.0, str(alt)]]:
		var r := Rect2(side[0] - 45, 280, 90, 32)
		o.draw_rect(r, g, false, 1.5)
		_text(o, Vector2(r.position.x, r.position.y + 25), side[1], 24, g, HORIZONTAL_ALIGNMENT_CENTER, 90)
	_text(o, Vector2(345, 332), "KTS", 14, g, HORIZONTAL_ALIGNMENT_CENTER, 90)
	_text(o, Vector2(845, 332), "FT", 14, g, HORIZONTAL_ALIGNMENT_CENTER, 90)
	if hook_down:
		_text(o, Vector2(420, 420), "HOOK", 20, g)
	if absf(px) > LANE_HALF and (st == St.APPROACH or st == St.WINDOW) and fmod(tt, 0.4) < 0.26:
		_text(o, Vector2(420, 395), "LINEUP", 20, Color(1, 0.45, 0.3, 0.95))

# --- Splash into the sea ---
func _splash_fx(o: Control) -> void:
	if splash_t < 0.0:
		return
	var u := clampf((splash_t - 0.2) / 0.9, 0.0, 1.0)
	_vgrad(o, Rect2(0, 0, 1280, 520), Color(0.06, 0.3, 0.36, 0.55 * u), Color(0.02, 0.12, 0.2, 0.9 * u))
	# light rays from the surface
	for k in range(5):
		var x0 := 200.0 + k * 230.0 + sin(tt * 0.7 + k) * 20.0
		o.draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 60, 0), Vector2(x0 + 160, 520), Vector2(x0 + 40, 520)]),
			Color(0.6, 0.9, 1.0, 0.05 * u))
	# spray
	for w in water_parts:
		var a := clampf(float(w["life"]) / float(w["max"]), 0.0, 1.0)
		var wp: Vector2 = w["p"]
		o.draw_circle(wp, float(w["r"]), Color(0.9, 0.96, 1.0, 0.75 * a))
		o.draw_circle(wp, float(w["r"]) * 2.2, Color(0.8, 0.9, 1.0, 0.18 * a))
	# water sheet across the canopy right at impact
	var sheet := clampf(1.0 - splash_t / 0.6, 0.0, 1.0)
	if sheet > 0.0:
		_vgrad(o, Rect2(0, 0, 1280, 520), Color(0.85, 0.95, 1.0, 0.7 * sheet), Color(0.6, 0.8, 0.95, 0.5 * sheet))
	# bubbles rising
	for k in range(34):
		var bx := fmod(k * 173.0 + sin(splash_t * 2.0 + k) * 12.0, 1180.0) + 50.0
		var by := 520.0 - fmod(splash_t * (90.0 + (k % 5) * 25.0) * 1.6 + k * 61.0, 520.0)
		var br := 3.0 + (k % 4) * 2.5
		o.draw_arc(Vector2(bx, by), br, 0, TAU, 16, Color(0.85, 0.95, 1.0, 0.45 * u), 1.5, true)
		o.draw_circle(Vector2(bx - br * 0.35, by - br * 0.35), br * 0.25, Color(1, 1, 1, 0.5 * u))
	# drips running down the glass
	for k in range(16):
		var dx := 80.0 + k * 75.0 + sin(k * 3.1) * 25.0
		var dy := fmod(splash_t * (140.0 + (k % 3) * 60.0) + k * 37.0, 560.0)
		o.draw_line(Vector2(dx, dy - 40), Vector2(dx, dy), Color(0.9, 0.97, 1.0, 0.25 * u), 2.0, true)

# --- Explosion ---
func _explosion(o: Control) -> void:
	var ctr := Vector2(640, 312)
	if fireball_t >= 0.0 and fireball_t < 2.4:
		var p := fireball_t / 2.4
		for k in range(8):
			var a := k * TAU / 8.0 + fireball_t * 0.6
			var off := Vector2(cos(a), sin(a) * 0.55) * (20.0 + p * 140.0)
			o.draw_circle(ctr + off + Vector2(0, -p * 80.0), 30.0 + p * 110.0, Color(0.22, 0.2, 0.2, (1.0 - p) * 0.5))
		for k in range(10):
			var r := (1.0 - k / 10.0) * (30.0 + p * 300.0)
			var heat := k / 10.0
			o.draw_circle(ctr, r, Color(1.0, 0.25 + heat * 0.65, heat * 0.5, maxf(0.0, 1.0 - p * 1.4) * 0.22))
		o.draw_circle(ctr, 20.0 + p * 60.0, Color(1, 1, 0.85, maxf(0.0, 1.0 - p * 2.2)))
		o.draw_arc(ctr, 40.0 + p * 500.0, 0, TAU, 64, Color(1, 0.95, 0.8, maxf(0.0, 1.0 - p * 2.5) * 0.6), 6.0, true)
	for pt in particles:
		var life: float = pt["life"]
		var a2 := clampf(life / float(pt["max"]), 0.0, 1.0)
		var pp: Vector2 = Vector2(pt["p"]) * 4.0
		if pt["smoke"]:
			o.draw_circle(pp, float(pt["s"]) * (12.0 - a2 * 6.0), Color(0.25, 0.23, 0.23, a2 * 0.6))
		else:
			o.draw_circle(pp, float(pt["s"]) * 1.6, Color(1, 0.5 + 0.45 * a2, 0.15, a2))
			o.draw_circle(pp, float(pt["s"]) * 4.0, Color(1, 0.5, 0.1, a2 * 0.2))

# --- Cockpit structure ---
func _panel_top(x: float) -> float:
	var u := (x - 640.0) / 640.0
	return 470.0 + 32.0 * u * u

func _cockpit(o: Control) -> void:
	var fr_dark := Color(0.055, 0.06, 0.068)
	var fr_mid := Color(0.13, 0.14, 0.155)
	var fr_hi := Color(0.32, 0.34, 0.37)
	# Canopy glass sheen
	o.draw_polygon(PackedVector2Array([Vector2(120, 0), Vector2(380, 0), Vector2(160, 470), Vector2(40, 470)]),
		PackedColorArray([Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.02)]))
	# Canopy bow
	var bow := PackedVector2Array()
	for i in range(33):
		var x := 1280.0 * i / 32.0
		var u := (x - 640.0) / 640.0
		bow.append(Vector2(x, 6.0 + 14.0 * u * u))
	bow.append(Vector2(1280, 0))
	bow.append(Vector2(0, 0))
	o.draw_colored_polygon(bow, fr_dark)
	# Side frames
	for sg in [1.0, -1.0]:
		var xo := 0.0 if sg > 0 else 1280.0
		var outer := PackedVector2Array([Vector2(xo, 0), Vector2(xo + 38 * sg, 0), Vector2(xo + 100 * sg, 512), Vector2(xo, 512)])
		o.draw_polygon(outer, PackedColorArray([fr_dark, fr_mid, fr_mid, fr_dark]))
		o.draw_line(Vector2(xo + 38 * sg, 0), Vector2(xo + 100 * sg, 512), fr_hi, 2.0, true)
		o.draw_line(Vector2(xo + 32 * sg, 0), Vector2(xo + 93 * sg, 512), Color(0, 0, 0, 0.6), 2.0, true)
		for k in range(7):
			var t := 0.08 + k * 0.13
			var bp := Vector2(xo + lerpf(20.0, 72.0, t) * sg, t * 512.0)
			o.draw_circle(bp, 3.2, Color(0.08, 0.085, 0.09))
			o.draw_circle(bp + Vector2(-0.8, -0.8), 2.0, fr_hi)
	# Glare shield
	var gs := PackedVector2Array()
	var gcol := PackedColorArray()
	for i in range(33):
		var x2 := 1280.0 * i / 32.0
		gs.append(Vector2(x2, _panel_top(x2)))
		gcol.append(Color(0.1, 0.105, 0.115))
	for i in range(32, -1, -1):
		var x3 := 1280.0 * i / 32.0
		gs.append(Vector2(x3, _panel_top(x3) + 22))
		gcol.append(Color(0.03, 0.032, 0.036))
	o.draw_polygon(gs, gcol)
	var edge := PackedVector2Array()
	for i in range(33):
		var x4 := 1280.0 * i / 32.0
		edge.append(Vector2(x4, _panel_top(x4)))
	o.draw_polyline(edge, Color(0.3, 0.32, 0.35), 2.0, true)
	# Panel body
	var body := PackedVector2Array()
	var bcol := PackedColorArray()
	for i in range(33):
		var x5 := 1280.0 * i / 32.0
		body.append(Vector2(x5, _panel_top(x5) + 22))
		bcol.append(Color(0.2, 0.21, 0.23))
	body.append(Vector2(1280, 720))
	bcol.append(Color(0.085, 0.09, 0.1))
	body.append(Vector2(0, 720))
	bcol.append(Color(0.085, 0.09, 0.1))
	o.draw_polygon(body, bcol)
	# Sub-panels behind instruments
	for r in [Rect2(78, 506, 190, 206), Rect2(276, 506, 180, 206), Rect2(462, 500, 356, 214), Rect2(824, 506, 234, 206), Rect2(1064, 506, 162, 206)]:
		_rrect(o, r, 8, Color(0.13, 0.135, 0.15))
		o.draw_line(r.position + Vector2(8, 0), Vector2(r.end.x - 8, r.position.y), Color(0.32, 0.34, 0.37), 1.0, true)
		for sp in [r.position + Vector2(10, 10), Vector2(r.end.x - 10, r.position.y + 10), Vector2(r.position.x + 10, r.end.y - 10), r.end - Vector2(10, 10)]:
			o.draw_circle(sp, 4.0, Color(0.36, 0.38, 0.41))
			o.draw_circle(sp, 3.0, Color(0.22, 0.23, 0.25))
			o.draw_line(sp - Vector2(2.2, 0), sp + Vector2(2.2, 0), Color(0.08, 0.08, 0.09), 1.0)
	_lens(o, Rect2(106, 524, 134, 172))
	_adi(o, Vector2(366, 612), 70.0)
	_mfd(o, Rect2(476, 512, 328, 190))
	_readouts(o, Rect2(840, 524, 202, 172))
	_lamps(o, Rect2(1080, 526, 130, 168))

func _glass(o: CanvasItem, r: Rect2) -> void:
	o.draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x * 0.55, 0), r.position + Vector2(0, r.size.y * 0.5)]), Color(1, 1, 1, 0.04))

func _lens(o: Control, r: Rect2) -> void:
	_rrect_border(o, r, 6, Color(0.02, 0.022, 0.025), Color(0.35, 0.37, 0.4), 2)
	_text(o, Vector2(r.position.x, r.position.y + 20), "BALL", 16, Color(0.75, 0.78, 0.8), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var cx := r.position.x + r.size.x * 0.5
	var top := r.position.y + 32
	var cell_h := 24.0
	var in_win := st == St.WINDOW
	for i in range(5):
		var cr := Rect2(cx - 26, top + i * cell_h, 52, cell_h - 3)
		_vgrad(o, cr, Color(0.14, 0.1, 0.04), Color(0.08, 0.06, 0.03))
	var cy := top + 2.5 * cell_h - 1.5
	var t3 := Z_PERFECT * 52.0
	o.draw_rect(Rect2(cx - 28, cy - t3, 56, t3 * 2), Color(0.3, 1, 0.35, 0.18 if in_win else 0.08))
	for i in range(4):
		for sx in [cx - 38 - i * 11, cx + 38 + i * 11]:
			o.draw_circle(Vector2(sx, cy), 7.0, Color(0.2, 1, 0.3, 0.18))
			o.draw_circle(Vector2(sx, cy), 4.0, Color(0.45, 1, 0.5))
	var off_lane := absf(px) > LANE_HALF and (st == St.APPROACH or st == St.WINDOW)
	if off_lane and fmod(tt, 0.4) < 0.25:
		for sx in [cx - 48, cx + 48]:
			for k in range(2):
				var wp := Vector2(sx, top + 14 + k * 16)
				o.draw_circle(wp, 9.0, Color(1, 0.1, 0.05, 0.25))
				o.draw_circle(wp, 5.0, Color(1, 0.2, 0.1))
	var b := clampf(_ball(), -1.1, 1.1)
	var by := cy - b * 52.0
	var low := b < Z_CRASH or b > Z_LATE
	var bc := Color(1, 0.15, 0.08) if low else Color(1, 0.66, 0.1)
	o.draw_circle(Vector2(cx, by), 22.0, Color(bc.r, bc.g, bc.b, 0.15))
	o.draw_circle(Vector2(cx, by), 14.0, Color(bc.r, bc.g, bc.b, 0.35))
	o.draw_circle(Vector2(cx, by), 9.0, bc)
	o.draw_circle(Vector2(cx - 2.5, by - 2.5), 3.5, Color(1, 1, 0.85))
	_glass(o, r)

func _adi(o: Control, ctr: Vector2, rad: float) -> void:
	o.draw_circle(ctr, rad + 14, Color(0.07, 0.075, 0.08))
	for k in range(6):
		o.draw_arc(ctr, rad + 12 - k * 2, 0, TAU, 64, Color(0.22 + k * 0.04, 0.23 + k * 0.04, 0.25 + k * 0.04), 2.0, true)
	var bank := _bank() * 2.5
	var off := clampf((pitch_px - jolt) * 1.6 + 8.0, -rad + 8, rad - 8)
	var n := 96
	var pts := []
	var inside := []
	for i in range(n):
		var a := TAU * i / n
		var p := Vector2(cos(a), sin(a)) * rad
		pts.append(p)
		inside.append(p.rotated(bank).y > off)
	var sky_poly := PackedVector2Array()
	var sky_cols := PackedColorArray()
	for i in range(n):
		sky_poly.append(ctr + pts[i])
		var yv: float = (pts[i].y + rad) / (2.0 * rad)
		sky_cols.append(Color(0.12, 0.38, 0.78).lerp(Color(0.45, 0.7, 0.95), yv))
	o.draw_polygon(sky_poly, sky_cols)
	var start := -1
	for i in range(n):
		if inside[i] and not inside[(i + n - 1) % n]:
			start = i
			break
	if start >= 0:
		var poly := PackedVector2Array()
		var cols := PackedColorArray()
		var i := start
		while inside[i]:
			poly.append(ctr + pts[i])
			var yv2: float = (pts[i].y + rad) / (2.0 * rad)
			cols.append(Color(0.55, 0.33, 0.14).lerp(Color(0.3, 0.17, 0.07), yv2))
			i = (i + 1) % n
			if i == start:
				break
		if poly.size() >= 3:
			o.draw_polygon(poly, cols)
	var hdir := Vector2(1, 0).rotated(-bank)
	var hn := Vector2(0, 1).rotated(-bank)
	var hc := ctr + hn * off
	o.draw_line(hc - hdir * rad * 0.98, hc + hdir * rad * 0.98, Color(1, 1, 1), 2.0, true)
	for k in [-2, -1, 1, 2]:
		var lc: Vector2 = hc - hn * (k * 16.0)
		var lw: float = 12.0 if abs(k) == 1 else 22.0
		o.draw_line(lc - hdir * lw, lc + hdir * lw, Color(1, 1, 1, 0.75), 1.5, true)
	for d in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a2 := deg_to_rad(float(d) - 90.0)
		var ln := 12.0 if d % 30 == 0 else 7.0
		o.draw_line(ctr + Vector2(cos(a2), sin(a2)) * rad, ctr + Vector2(cos(a2), sin(a2)) * (rad - ln), Color(1, 1, 1), 2.0, true)
	var w := Color(1, 0.62, 0.1)
	o.draw_line(ctr + Vector2(-44, 0), ctr + Vector2(-16, 0), w, 4.0, true)
	o.draw_line(ctr + Vector2(16, 0), ctr + Vector2(44, 0), w, 4.0, true)
	o.draw_line(ctr + Vector2(-16, 0), ctr + Vector2(-8, 8), w, 4.0, true)
	o.draw_line(ctr + Vector2(16, 0), ctr + Vector2(8, 8), w, 4.0, true)
	o.draw_circle(ctr, 3.5, w)
	o.draw_arc(ctr, rad - 4, PI * 1.1, PI * 1.55, 24, Color(1, 1, 1, 0.12), 6.0, true)

func _mfd(o: Control, r: Rect2) -> void:
	# Bezel with pushbuttons
	_rrect_border(o, r, 10, Color(0.1, 0.105, 0.115), Color(0.3, 0.32, 0.35), 2)
	var scr := r.grow(-26)
	for i in range(5):
		var bx := scr.position.x + 20 + i * (scr.size.x - 40) / 4.0
		for byy in [r.position.y + 6, r.end.y - 20]:
			_rrect(o, Rect2(bx - 14, byy, 28, 14), 3, Color(0.2, 0.21, 0.23))
			o.draw_line(Vector2(bx - 12, byy + 1), Vector2(bx + 12, byy + 1), Color(0.38, 0.4, 0.43), 1.0)
	for i in range(3):
		var byy2 := scr.position.y + 20 + i * (scr.size.y - 40) / 2.0
		for bxx in [r.position.x + 6, r.end.x - 20]:
			_rrect(o, Rect2(bxx, byy2 - 12, 14, 24), 3, Color(0.2, 0.21, 0.23))
	o.draw_rect(scr, Color(0.01, 0.03, 0.015))
	var g := Color(0.4, 1.0, 0.5)
	var gd := Color(0.2, 0.55, 0.28)
	var glow := Color(0.3, 1.0, 0.4, 0.15)
	_text(o, Vector2(scr.position.x + 8, scr.position.y + 18), "CV LINEUP", 14, gd)
	_text(o, Vector2(scr.end.x - 108, scr.position.y + 18), "RNG %.2f" % (maxf(dist, 0.0) / 1852.0), 14, g)
	# Plan view: carrier moves down the screen as you close; lateral scale exaggerated
	var ac := Vector2(scr.position.x + scr.size.x * 0.5, scr.end.y - 18)
	var kz := (scr.size.y - 40) / (760.0 + 340.0)
	var kx := kz * 3.0
	var poly := PackedVector2Array()
	for p in deck_l:
		poly.append(Vector2(ac.x + (p.x - px) * kx, ac.y - (p.y + dist) * kz))
	var clip := Rect2(scr.position + Vector2(2, 24), scr.size - Vector2(4, 26))
	var visible_poly := Geometry2D.intersect_polygons(poly, PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)]))
	for vp in visible_poly:
		o.draw_colored_polygon(vp, Color(0.2, 0.8, 0.3, 0.12))
		var closed := vp.duplicate()
		closed.append(vp[0])
		o.draw_polyline(closed, glow, 4.0, true)
		o.draw_polyline(closed, g, 1.5, true)
	var l0 := Vector2(ac.x - px * kx, ac.y - dist * kz)
	var l1 := Vector2(ac.x - px * kx, ac.y - (dist + LANE_LEN) * kz)
	var yy := minf(l0.y, clip.end.y)
	var y_end := maxf(l1.y, clip.position.y)
	while yy > y_end:
		o.draw_line(Vector2(l0.x, yy), Vector2(l0.x, maxf(yy - 5, y_end)), gd, 1.0)
		yy -= 10
	# Extended centerline down to the aircraft
	var yy2 := clip.end.y
	while yy2 > maxf(l0.y, clip.position.y):
		o.draw_line(Vector2(l0.x, yy2), Vector2(l0.x, yy2 - 4), Color(0.3, 0.8, 0.4, 0.5), 1.0)
		yy2 -= 9
	var off_lane := absf(px) > LANE_HALF
	var acol := Color(1, 0.35, 0.2) if (off_lane and fmod(tt, 0.4) < 0.25) else g
	o.draw_line(ac + Vector2(0, -12), ac + Vector2(0, 10), acol, 2.5, true)
	o.draw_line(ac + Vector2(-13, 0), ac + Vector2(13, 0), acol, 2.5, true)
	o.draw_line(ac + Vector2(-6, 9), ac + Vector2(6, 9), acol, 2.5, true)
	# Wind arrow
	var wa := Vector2(scr.position.x + 30, scr.end.y - 22)
	var wl := clampf(wind * 5.0, -24, 24)
	o.draw_line(wa, wa + Vector2(wl, 0), gd, 2.0, true)
	if absf(wl) > 3:
		var s := signf(wl)
		o.draw_colored_polygon(PackedVector2Array([wa + Vector2(wl + 6 * s, 0), wa + Vector2(wl, -4), wa + Vector2(wl, 4)]), gd)
	_text(o, Vector2(wa.x - 18, wa.y - 8), "WIND", 11, gd)
	var sy := scr.position.y
	while sy < scr.end.y:
		o.draw_line(Vector2(scr.position.x, sy), Vector2(scr.end.x, sy), Color(0, 0, 0, 0.22), 1.0)
		sy += 3.0
	_glass(o, scr)

func _readouts(o: Control, r: Rect2) -> void:
	_rrect_border(o, r, 6, Color(0.01, 0.03, 0.015), Color(0.3, 0.32, 0.35), 2)
	var g := Color(0.4, 1.0, 0.5)
	var gd := Color(0.2, 0.55, 0.28)
	var ghost := Color(0.2, 0.6, 0.3, 0.08)
	var rng := maxf(dist, 0.0) / 1852.0
	var alt := maxi(int((_eye_y() - DECK_H) * 3.28), 0)
	var wk := int(absf(wind) * 3.0)
	var wdir := "L" if wind < -0.3 else ("R" if wind > 0.3 else "")
	var rows := [["SPD", "%d" % int(spd * 1.944), "KT"], ["ALT", "%d" % alt, "FT"], ["RNG", "%.2f" % rng, "NM"], ["WND", "%s%d" % [wdir, wk], "KT"]]
	for i in range(rows.size()):
		var y := r.position.y + 36 + i * 38
		_text(o, Vector2(r.position.x + 12, y), rows[i][0], 16, gd)
		_text(o, Vector2(r.position.x + 58, y), "8888", 28, ghost, HORIZONTAL_ALIGNMENT_RIGHT, 100)
		_text(o, Vector2(r.position.x + 58, y), rows[i][1], 28, g, HORIZONTAL_ALIGNMENT_RIGHT, 100)
		_text(o, Vector2(r.position.x + 164, y), rows[i][2], 13, gd)
	_glass(o, r)

func _lamp(o: Control, r: Rect2, t: String, on: bool, col: Color) -> void:
	if on:
		_rrect(o, r.grow(6), 8, Color(col.r, col.g, col.b, 0.15))
		_vgrad(o, r, col.lightened(0.25), col)
	else:
		_vgrad(o, r, Color(col.r * 0.22, col.g * 0.22, col.b * 0.22), Color(col.r * 0.12, col.g * 0.12, col.b * 0.12))
	o.draw_rect(r, Color(0.05, 0.05, 0.06), false, 2.0)
	var tc := Color(0.05, 0.05, 0.05) if on else Color(col.r * 0.5, col.g * 0.5, col.b * 0.5)
	_text(o, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 7), t, 18, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _lamps(o: Control, r: Rect2) -> void:
	var off_lane := absf(px) > LANE_HALF and (st == St.APPROACH or st == St.WINDOW)
	var blink := fmod(tt, 0.5) < 0.3
	_lamp(o, Rect2(r.position.x, r.position.y, r.size.x, 44), "HOOK", hook_down, Color(0.3, 0.95, 0.4))
	_lamp(o, Rect2(r.position.x, r.position.y + 62, r.size.x, 44), "WAVE OFF", off_lane and blink, Color(1, 0.22, 0.15))
	_lamp(o, Rect2(r.position.x, r.position.y + 124, r.size.x, 44), "LEVEL %d" % level, true, Color(1, 0.72, 0.2))

# --- Messages ---
func _callouts(o: Control) -> void:
	var blink := fmod(tt, 0.4) < 0.26
	match st:
		St.APPROACH:
			if st_t < 3.0:
				_text_c(o, 640, 150, "LINE UP ON THE DECK", 30, Color(1, 1, 1), 6)
		St.WINDOW:
			if blink:
				_text_c(o, 640, 152, "DROP THE HOOK!", 52, Color(1, 0.82, 0.2), 8)
			_text_c(o, 640, 190, "PRESS BOTH FLIPPERS WHEN THE BALL IS CENTERED", 22, Color(1, 1, 1), 5)
		St.COMMITTED, St.TOUCHDOWN:
			if result != "crash" and result != "splash":
				_text_c(o, 640, 152, "HOOK DOWN", 44, Color(0.45, 1, 0.55), 7)
	if (st == St.APPROACH or st == St.WINDOW) and absf(px) > LANE_HALF and blink:
		_text_c(o, 640, 450, "<< COME LEFT" if px > 0 else "COME RIGHT >>", 30, Color(1, 0.35, 0.2), 6)

func _wait(o: Control) -> void:
	o.draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.45))
	if fmod(tt, 0.8) < 0.5:
		_text_c(o, 640, 300, "STAND BY", 44, Color(1, 1, 1), 6)

func _intro(o: Control) -> void:
	_vgrad(o, Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.45))
	_text_c(o, 640, 120, "CARRIER LANDING", 76, Color(1, 0.75, 0.2), 10)
	_text_c(o, 640, 180, "LEVEL %d  -  %s" % [level, LEVEL_NAME[level]], 36, Color(1, 1, 1), 6)
	_text_c(o, 640, 270, "HOLD A FLIPPER TO FIGHT THE CROSSWIND", 26, Color(0.7, 1, 0.75), 5)
	_text_c(o, 640, 310, "WATCH THE BALL ON YOUR PANEL", 26, Color(0.7, 1, 0.75), 5)
	_text_c(o, 640, 350, "PRESS BOTH FLIPPERS WHEN IT'S CENTERED", 26, Color(0.7, 1, 0.75), 5)
	var n := maxi(int(ceil(INTRO_TIME - st_t)), 1)
	_text_c(o, 640, 450, str(n), 80, Color(1, 0.85, 0.25, 1.0 if fmod(tt, 0.5) < 0.35 else 0.55), 10)

func _result_ui(o: Control) -> void:
	var info: Dictionary = RESULTS.get(result, RESULTS["crash"])
	var good := result.begins_with("wire")
	var col := Color(0.45, 1, 0.5) if result == "wire_3" else (Color(1, 0.8, 0.25) if good else Color(1, 0.32, 0.22))
	var a := clampf(st_t * 3.0, 0.0, 1.0) if st == St.RESULT else 1.0
	_vgrad(o, Rect2(0, 110, 1280, 170), Color(0, 0, 0, 0.3 * a), Color(0, 0, 0, 0.78 * a))
	_vgrad(o, Rect2(0, 280, 1280, 170), Color(0, 0, 0, 0.78 * a), Color(0, 0, 0, 0.3 * a))
	o.draw_line(Vector2(200, 112), Vector2(1080, 112), Color(col.r, col.g, col.b, 0.6 * a), 2.0)
	o.draw_line(Vector2(200, 448), Vector2(1080, 448), Color(col.r, col.g, col.b, 0.6 * a), 2.0)
	var pulse := 1.0 if result != "wire_3" else 0.75 + 0.25 * absf(sin(tt * 5.0))
	_text_c(o, 640, 250, info["title"], 104, Color(col.r, col.g, col.b, a * pulse), 12)
	var sub: String = info["sub"] if result != "crash" else crash_reason
	_text_c(o, 640, 305, sub, 30, Color(1, 1, 1, a), 6)
	var award := int(float(info["award"]) * float(LEVEL_MULT[level]))
	if award > 0:
		_text_c(o, 640, 385, _comma(award), 64, Color(1, 0.88, 0.3, a), 8)
		if level > 1:
			_text_c(o, 640, 428, "LEVEL %d  x%.1f" % [level, float(LEVEL_MULT[level])], 24, Color(0.85, 0.85, 0.85, a), 4)
