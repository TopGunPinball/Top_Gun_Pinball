# PlayerTurnHighlighter.gd
extends Control

@export_range(1, 4) var max_players: int = 4
@export var pulse_alpha: bool = true      # enable color flash (uses pulse_color)
@export var pulse_scale: bool = true      # gentle size bob on active label
@export var pulse_speed: float = 0.4      # seconds per half-pulse
@export var pulse_color: Color = Color(1.3, 1.3, 0.0, 1.0)  # pure bright yellow
@export var inactive_tint: Color = Color(0.4, 0.4, 0.4, 1.0)  # dim color for inactives

var _active_player: int = 1
var _pulse_tween: Tween

@onready var _labels := {
    1: ($P1Label as Label),
    2: ($P2Label as Label),
    3: ($P3Label as Label),
    4: ($P4Label as Label)
}

func _ready() -> void:
    # Show only labels up to max_players
    for i in [1, 2, 3, 4]:
        if _labels.has(i):
            var l: Label = _labels[i]
            l.visible = (i <= max_players)

    _set_active_player(1)  # default highlight

    # Optional: listen for MPF bus events if you have an autoload called MPFBus
    if Engine.has_singleton("MPFBus"):
        var bus = Engine.get_singleton("MPFBus")
        # Signal signature: mpf_event(event_name: String, params: Dictionary)
        bus.mpf_event.connect(_on_mpf_event)

func _on_mpf_event(event_name: String, params: Dictionary) -> void:
    match event_name:
        "ui_player_1_up": _set_active_player(1)
        "ui_player_2_up": _set_active_player(2)
        "ui_player_3_up": _set_active_player(3)
        "ui_player_4_up": _set_active_player(4)
        _:
            pass

func _set_active_player(n: int) -> void:
    if n < 1 or n > max_players:
        push_warning("Active player %s out of range (max %s)" % [n, max_players])
        return
    _active_player = n

    # Reset all labels; dim inactives, brighten active; only active will pulse
    for i in [1, 2, 3, 4]:
        if not _labels.has(i): continue
        var l: Label = _labels[i]
        l.visible = (i <= max_players)
        l.scale = Vector2.ONE

        if i == n:
            # Active player: bright white, outline on
            l.modulate = Color(1, 1, 1, 1)
            l.set("theme_override_constants/outline_size", 4)
            l.set("theme_override_colors/font_outline_color", Color(1, 1, 1, 1))
        else:
            # Inactive player: dim grey, outline off
            l.modulate = inactive_tint
            l.set("theme_override_constants/outline_size", 0)

    # Start pulse *only* on the active label
    _apply_pulse(_labels[n])

func _apply_pulse(lbl: CanvasItem) -> void:
    # Kill any existing pulse
    if is_instance_valid(_pulse_tween):
        _pulse_tween.kill()

    # Ensure starting state
    lbl.scale = Vector2.ONE
    lbl.modulate = Color(1, 1, 1, 1)  # start white

    # Build a looping tween for the active label
    _pulse_tween = create_tween().set_loops()

    if pulse_alpha:
        # Flash between white and pulse_color (full RGB), then back
        _pulse_tween.tween_property(lbl, "modulate", pulse_color, pulse_speed)
        _pulse_tween.tween_property(lbl, "modulate", Color(1, 1, 1, 1), pulse_speed)

    if pulse_scale:
        _pulse_tween.parallel().tween_property(lbl, "scale", Vector2(1.06, 1.06), pulse_speed)
        _pulse_tween.parallel().tween_property(lbl, "scale", Vector2(1.00, 1.00), pulse_speed)
