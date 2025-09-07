extends Label
class_name MPFVariable

const VariableType = preload("const.gd").VariableType
const numbered_players = [VariableType.PLAYER_1, VariableType.PLAYER_2, VariableType.PLAYER_3, VariableType.PLAYER_4]

## Displays a player, machine, or event variable as text on screen.

## The source of the variable value.
@export var variable_type: VariableType = VariableType.CURRENT_PLAYER
## The name of the variable or event arg to show.
@export var variable_name: String
## If checked, number values will be comma-separated into thousands.
@export var comma_separate: bool
## If greater than zero, numbers will be left-padded with zeroes to this minimum number of digits.
@export var min_digits: int = -1
## A template string for substituting the variable value into. Use "%s" as the replacement value.
@export var template_string: String = ""
## A format string for formatting the variable value or event args into.
@export var format_string: String = ""
## If checked, this node will show no text until an update sets a value on it.
@export var initialize_empty: bool = true
## The name of an MPF event to subscribe to for getting new variable values.
@export var update_event: String = ""
## If set, this node will only render if the number of players is greater than or equal to this value.
@export var min_players: int
## If set, this node will only render if the number of players is less than or equal to this value.
@export var max_players: int

# --- NEW: highlight controls ---
@export var highlight_when_active: bool = true
@export var active_font_color: Color = Color(1, 1, 0, 1)        # yellow
@export var inactive_font_color: Color = Color(0.6, 0.6, 0.6, 1) # gray
@export var turn_poll_interval: float = 0.20                    # seconds

# --- NEW: where to paint the color (e.g., P1ScoreLabel) ---
@export var target_label_path: NodePath
@onready var target_label: Label = get_node_or_null(target_label_path) as Label

var var_template: String = "%s"
var player_number: int = -1
var _initial_text: String = ""
var _poll_accum: float = 0.0

func _init():
  _initial_text = self.text

func _enter_tree():
  if initialize_empty and self.text == _initial_text and not Engine.is_editor_hint():
    self.text = ""

func _ready() -> void:
  if min_digits > 0:
    var_template = ("%0" + str(min_digits) + "d")
  if variable_type == VariableType.MACHINE_VAR:
    self.update_text(MPF.game.machine_vars.get(self.variable_name))
    MPF.game.connect("machine_update", self._on_machine_update)
  elif variable_type == VariableType.EVENT_ARG:
    var parent_slide = MPF.util.find_parent_slide_or_widget(self)
    parent_slide.register_updater(self)
  else:
    var is_current_player = self._calculate_player_value()
    if is_current_player:
      MPF.game.connect("player_update", self._on_player_update)

  if self.update_event:
    MPF.server.add_event_handler(self.update_event, self.update)

  if min_players or max_players or variable_type in numbered_players:
    MPF.game.connect("player_added", self._on_player_added)
    self._on_player_added(MPF.game.num_players)

  set_process(true)
  _apply_active_style()

func _exit_tree() -> void:
  if self.update_event:
    MPF.server.remove_event_handler(self.update_event, self.update)
  if variable_type == VariableType.EVENT_ARG:
    var parent_slide = MPF.util.find_parent_slide_or_widget(self)
    parent_slide.remove_updater(self)

func update(settings: Dictionary, kwargs: Dictionary = {}) -> void:
  if variable_type != VariableType.EVENT_ARG:
    return
  if self.format_string:
    if not kwargs.is_empty() or not settings.get("tokens", {}).is_empty():
      settings = settings.duplicate()
      settings.merge(settings.get("tokens", {}))
      settings.merge(kwargs)
    self.update_text(settings)
    return
  if variable_name in kwargs:
    self.update_text(kwargs[variable_name])
  elif variable_name in settings.get("tokens", {}):
    self.update_text(settings.tokens[variable_name])
  elif variable_name in settings:
    self.update_text(settings[variable_name])

func update_text(value) -> void:
  if self.format_string:
    match variable_type:
      VariableType.CURRENT_PLAYER:
        value = MPF.game.player
      VariableType.MACHINE_VAR:
        value = MPF.game.machine_vars
      VariableType.SETTING:
        value = MPF.game.settings
      _:
        if variable_type in numbered_players:
          value = MPF.game.players[numbered_players.find(variable_type)]
    self.text = format_string.format(value)
    _apply_active_style()
    return

  if value == null:
    self.text = ""
    _apply_active_style()
    return

  if value is int or value is float:
    if comma_separate and value >= 1000:
      value = MPF.util.comma_sep(value)
    elif not template_string:
      value = var_template % value

  if template_string:
    self.text = template_string % value
  else:
    self.text = value

  _apply_active_style()

func _on_machine_update(var_name: String, value: Variant) -> void:
  if var_name == variable_name:
    self.update_text(value)

func _on_player_update(var_name: String, value: Variant) -> void:
  if var_name == variable_name:
    self.update_text(value)

func _on_player_added(total_players: int) -> void:
  if min_players > 0 and min_players > total_players:
    self.hide()
  elif max_players > 0 and total_players > max_players:
    self.hide()
  elif self.player_number > total_players:
    self.hide()
  else:
    self._calculate_player_value()
    self.show()
    _apply_active_style()

func _calculate_player_value() -> bool:
  var mpf_player_num = MPF.game.player.get("number")
  if not mpf_player_num:
    MPF.log.warning("MPFVariable '%s' is a player variable and should only exist in game modes.", self.name)
    return false
  if variable_type == VariableType.CURRENT_PLAYER:
    self.player_number = mpf_player_num
  elif variable_type in numbered_players:
    self.player_number = numbered_players.find(variable_type) + 1
  var is_current_player = self.player_number == MPF.game.player.get("number")
  if is_current_player:
    self.update_text(MPF.game.player.get(self.variable_name))
    return true
  elif MPF.game.players.size() >= self.player_number:
    self.update_text(MPF.game.players[self.player_number - 1].get(self.variable_name))
  return false

func _process(delta: float) -> void:
  if not highlight_when_active:
    return
  _poll_accum += delta
  if _poll_accum >= turn_poll_interval:
    _poll_accum = 0.0
    _apply_active_style()

func _apply_active_style() -> void:
  if not highlight_when_active:
    return
  if MPF == null or MPF.game == null or MPF.game.player == null:
    return

  var current_num = MPF.game.player.get("number")
  if current_num == null:
    return

  var this_num = self.player_number
  if variable_type == VariableType.CURRENT_PLAYER:
    this_num = int(current_num)

  var is_active = int(this_num) == int(current_num)

  # Paint the target label if provided; otherwise paint self.
  var lbl: Label = target_label
  if lbl == null:
    lbl = self

  if is_active:
    lbl.add_theme_color_override("font_color", active_font_color)
  else:
    lbl.add_theme_color_override("font_color", inactive_font_color)
