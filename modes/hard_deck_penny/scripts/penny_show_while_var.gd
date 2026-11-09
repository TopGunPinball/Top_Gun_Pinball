extends Control
## Shows this node (and everything under it) only while a player variable
## equals show_value. Used on the penny_window slide so the countdown is only
## visible while the window timer is running (penny_window_timer_on, set by
## hard_deck_penny.yaml).

@export var variable_name: String = "penny_window_timer_on"
@export var show_value: int = 1


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	MPF.game.player_update.connect(_on_player_update)
	_refresh()


func _exit_tree() -> void:
	if MPF and MPF.game and MPF.game.player_update.is_connected(_on_player_update):
		MPF.game.player_update.disconnect(_on_player_update)


func _on_player_update(var_key: String, _value) -> void:
	if var_key == variable_name:
		_refresh()


func _refresh() -> void:
	var v = 0
	if MPF.game and MPF.game.player:
		v = MPF.game.player.get(variable_name, 0)
	visible = int(v) == show_value
