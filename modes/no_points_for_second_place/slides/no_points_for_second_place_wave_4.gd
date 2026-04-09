extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

func _ready() -> void:
    _update()
    MPF.game.player_update.connect(_on_var_changed)

func _exit_tree() -> void:
    super._exit_tree()
    if MPF.game.player_update.is_connected(_on_var_changed):
        MPF.game.player_update.disconnect(_on_var_changed)

func _on_var_changed(var_key: String, _value) -> void:
    if "goose_letter" in var_key:
        _update()

func _update() -> void:
    var p = MPF.game.player
    $w4_g_shot.visible   = p.get("goose_letter_g",       1) == 1
    $w4_ol_shot.visible  = p.get("goose_letter_o_left",  1) == 1
    $w4_or_shot.visible  = p.get("goose_letter_o_right", 1) == 1
    $w4_s_shot.visible   = p.get("goose_letter_s",       1) == 1
    $w4_e_shot.visible   = p.get("goose_letter_e",       1) == 1
