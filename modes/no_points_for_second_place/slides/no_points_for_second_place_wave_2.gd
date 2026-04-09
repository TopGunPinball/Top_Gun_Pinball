extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

func _ready() -> void:
    _update()
    MPF.game.player_update.connect(_on_var_changed)

func _exit_tree() -> void:
    super._exit_tree()
    if MPF.game.player_update.is_connected(_on_var_changed):
        MPF.game.player_update.disconnect(_on_var_changed)

func _on_var_changed(var_key: String, _value) -> void:
    if "wave2" in var_key:
        _update()

func _update() -> void:
    var p = MPF.game.player
    $w2_l_shot.visible          = p.get("no_points_for_second_place_wave2_l_hit",        0) == 0
    $w2_o_shot.visible          = p.get("no_points_for_second_place_wave2_o_hit",        0) == 0
    $w2_c_shot.visible          = p.get("no_points_for_second_place_wave2_c_hit",        0) == 0
    $w2_k_shot.visible          = p.get("no_points_for_second_place_wave2_k_hit",        0) == 0
    $w2_c_iceman_shot.visible   = p.get("no_points_for_second_place_wave2_iceman_c_hit", 0) == 0
    $w2_a_iceman_shot.visible   = p.get("no_points_for_second_place_wave2_iceman_a_hit", 0) == 0
