extends Control
## Controls which player score label is visible based on whose turn it is.
## Only the current player's PxScoreLabel is shown — the others are hidden.
##
## Uses call_deferred on player_update so our visibility override runs AFTER
## MPFVariable has processed its own player_update callback (which re-shows
## labels based on min_players). Without defer, MPFVariable wins the race.

var _current_player: int = 1

func _ready() -> void:
    MPF.server.add_event_handler("player_turn_started", _on_player_turn_started)
    MPF.game.connect("player_update", _on_player_update)
    MPF.game.connect("machine_update", _on_player_update)
    if MPF.game.player:
        _current_player = MPF.game.player.number
    _apply_visibility()

func _on_player_turn_started(kwargs: Dictionary) -> void:
    _current_player = int(kwargs.get("number", _current_player))
    _apply_visibility()

func _on_player_update(_data = null, _extra = null) -> void:
    # Deferred so we run after MPFVariable's own player_update handler
    call_deferred("_apply_visibility")

func _apply_visibility() -> void:
    $P1ScoreLabel.visible = (_current_player == 1)
    $P2ScoreLabel.visible = (_current_player == 2)
    $P3ScoreLabel.visible = (_current_player == 3)
    $P4ScoreLabel.visible = (_current_player == 4)
