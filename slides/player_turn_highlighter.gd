# ScoreColorByChange.gd  (Godot 4.x)
# Attach this to the parent node that contains P1Score, P2Score, ... labels.
extends Control

@export var active_color: Color = Color(1, 1, 0, 1)      # bright yellow
@export var inactive_color: Color = Color(0.6, 0.6, 0.6, 1)
@export_range(1, 4) var players: int = 2                  # set to 2, 3, or 4
@export var check_every_seconds: float = 0.20             # how often to check text changes

# Drag/assign these in the Inspector (leave unused ones empty)
@export var p1_label_path: NodePath
@export var p2_label_path: NodePath
@export var p3_label_path: NodePath
@export var p4_label_path: NodePath

@onready var p1_label: Label = get_node_or_null(p1_label_path) as Label
@onready var p2_label: Label = get_node_or_null(p2_label_path) as Label
@onready var p3_label: Label = get_node_or_null(p3_label_path) as Label
@onready var p4_label: Label = get_node_or_null(p4_label_path) as Label

var _active_player: int = 1
var _last_scores: Dictionary = {}   # player_index -> int score
var _accum: float = 0.0

func _ready() -> void:
  # paint initial colors
  _apply_colors()
  # capture starting score values
  _capture_initial_scores()

func _process(delta: float) -> void:
  _accum += delta
  if _accum < check_every_seconds:
    return
  _accum = 0.0
  _check_for_score_changes()

func _capture_initial_scores() -> void:
  for i in range(1, players + 1):
    _last_scores[i] = _read_score(_get_label(i))

func _check_for_score_changes() -> void:
  for i in range(1, players + 1):
    var lbl: Label = _get_label(i)
    if lbl == null:
      continue
    var current: int = _read_score(lbl)
    var previous: int = int(_last_scores.get(i, current))
    if current != previous:
      _last_scores[i] = current
      # If this player's score went up, consider them the active one
      if current > previous:
        _set_active_player(i)

func _get_label(i: int) -> Label:
  match i:
    1: return p1_label
    2: return p2_label
    3: return p3_label
    4: return p4_label
    _: return null

func _read_score(lbl: Label) -> int:
  if lbl == null:
    return 0
  # Try to parse digits from the label text (handles "12,345" or "SCORE: 12345")
  var t: String = lbl.text
  var digits: String = ""
  for c in t:
    if c >= '0' and c <= '9':
      digits += c
  if digits == "":
    return 0
  return int(digits)

func _set_active_player(n: int) -> void:
  if n == _active_player:
    return
  _active_player = n
  _apply_colors()

func _apply_colors() -> void:
  _paint_label(p1_label, 1)
  _paint_label(p2_label, 2)
  _paint_label(p3_label, 3)
  _paint_label(p4_label, 4)

func _paint_label(lbl: Label, player_index: int) -> void:
  if lbl == null or player_index > players:
    return
  var col: Color = active_color if player_index == _active_player else inactive_color
  lbl.add_theme_color_override("font_color", col)
