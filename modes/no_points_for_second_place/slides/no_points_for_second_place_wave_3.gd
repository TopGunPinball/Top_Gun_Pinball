extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

func _ready() -> void:
    _update()
    MPF.game.player_update.connect(_on_var_changed)

func _exit_tree() -> void:
    super._exit_tree()
    if MPF.game.player_update.is_connected(_on_var_changed):
        MPF.game.player_update.disconnect(_on_var_changed)

func _on_var_changed(var_key: String, _value) -> void:
    if "wave3" in var_key:
        _update()

func _update() -> void:
    var p = MPF.game.player
    $w3_left_lane_shot.visible  = p.get("no_points_for_second_place_wave3_lr_hit",  0) == 0
    $w3_top_loop_shot.visible   = p.get("no_points_for_second_place_wave3_tl_hit",  0) == 0
    $w3_top_ramp_shot.visible   = p.get("no_points_for_second_place_wave3_rr_hit",  0) == 0
