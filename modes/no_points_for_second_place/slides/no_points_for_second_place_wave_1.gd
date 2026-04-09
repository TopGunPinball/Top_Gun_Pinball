extends "res://addons/mpf-gmc/classes/mpf_slide.gd"

func _ready() -> void:
    _update()
    MPF.game.player_update.connect(_on_var_changed)

func _exit_tree() -> void:
    super._exit_tree()
    if MPF.game.player_update.is_connected(_on_var_changed):
        MPF.game.player_update.disconnect(_on_var_changed)

func _on_var_changed(var_key: String, _value) -> void:
    if "wave1" in var_key:
        _update()

func _update() -> void:
    var p = MPF.game.player
    print("UPDATE: lr=%s rr=%s sp=%s twr=%s" % [
        p.get("no_points_for_second_place_wave1_lr_hit", "MISSING"),
        p.get("no_points_for_second_place_wave1_rr_hit", "MISSING"),
        p.get("no_points_for_second_place_wave1_sp_hit",  "MISSING"),
        p.get("no_points_for_second_place_wave1_twr_hit", "MISSING")
    ])
    $w1_left_ramp_shot.visible  = p.get("no_points_for_second_place_wave1_lr_hit",  0) == 0
    $w1_right_ramp_shot.visible = p.get("no_points_for_second_place_wave1_rr_hit",  0) == 0
    $w1_spinner_shot.visible    = p.get("no_points_for_second_place_wave1_sp_hit",   0) == 0
    $w1_tower_shot.visible      = p.get("no_points_for_second_place_wave1_twr_hit",  0) == 0
