extends Control

##############################################################################
## High Score Name Entry Controller
## File: modes/high_score/slides/high_score_entry.gd
## ATTACH TO: the EntryController node inside high_score_entry.tscn
##
## Signal confirmed from mpf_variable.gd source:
##   MPF.game.connect("machine_update", _on_machine_update)
##   MPF.game.machine_vars.get("var_name") -> current value
##
## Node children expected (siblings NOT children — see get_parent()):
##   ../NameDisplay       Label — current typed name + cursor
##   ../CarouselPrev      Label — letter to the left (dimmed)
##   ../CarouselCurrent   Label — selected letter (bright, large font)
##   ../CarouselNext      Label — letter to the right (dimmed)
##   ../TimerLabel        Label — countdown seconds
##############################################################################

const MAX_NAME_LENGTH := 20
const TIMER_SECONDS   := 20.0
const TOTAL_CHARS     := 29   # 0–28

const CHAR_DISPLAY := [
    "A","B","C","D","E","F","G","H","I","J","K","L","M",
    "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
    "SPACE", "◄ BACK", "FINISH"
]
const CHAR_VALUES := [
    "A","B","C","D","E","F","G","H","I","J","K","L","M",
    "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
    " ", "BACK", "FINISH"
]

var _letter_index    : int    = 0
# Last hs_select_trigger value handled. MPF sets the var to 0 at the start of
# EVERY entry and adds 1 per Start press, so presses are always 1, 2, 3...
var _select_trigger  : int    = 0
var _player_num      : int    = 0
var _typed_name      : String = ""
var _timer_remaining : float  = TIMER_SECONDS
var _active          : bool   = false
var _submitted       : bool   = false

func _ready() -> void:
    # The slide is created ONCE and reused for every player who qualifies
    # (GMC keeps the existing slide on a repeat "play"), so _ready only
    # covers the first entry. Later entries are reset in _reset_for_new_entry.
    _player_num = int(MPF.game.machine_vars.get("hs_player_num", 0))
    _reset_for_new_entry()
    _letter_index   = int(MPF.game.machine_vars.get("hs_letter_index", 0))
    _select_trigger = int(MPF.game.machine_vars.get("hs_select_trigger", 0))
    _update_carousel()

    MPF.game.connect("machine_update", _on_machine_update)

    # Listen for each new entry prompt (fires each time a new player needs to enter)
    MPF.server.add_event_handler("high_score_enter_initials", _on_entry_start)

func _exit_tree() -> void:
    if MPF.game.is_connected("machine_update", _on_machine_update):
        MPF.game.disconnect("machine_update", _on_machine_update)
    MPF.server.remove_event_handler("high_score_enter_initials", _on_entry_start)

func _process(delta: float) -> void:
    if not _active or _submitted:
        return
    _timer_remaining -= delta
    if _timer_remaining <= 0.0:
        _timer_remaining = 0.0
        _submit_name()
    else:
        _update_timer_display()

# Called each time a new player's entry starts.
# GMC calls event handlers with ONE argument (the event kwargs). The old
# two-argument signature made every call fail, so player 2 inherited
# player 1's finished entry (name "RAB", already submitted = locked).
func _on_entry_start(_kwargs: Dictionary = {}) -> void:
    _reset_for_new_entry()

# Clean slate for the next player. Safe to run more than once per entry
# (event handler + hs_player_num change both call it at prompt start).
func _reset_for_new_entry() -> void:
    _typed_name      = ""
    _letter_index    = 0
    _select_trigger  = 0
    _timer_remaining = TIMER_SECONDS
    _submitted = false
    _active    = true
    _update_carousel()
    _update_name_display()
    _update_timer_display()

func _on_machine_update(var_name: String, value: Variant) -> void:
    match var_name:
        "hs_player_num":
            # Backup reset: a different player is now entering a name
            var pnum = int(value)
            if pnum != _player_num:
                _player_num = pnum
                _reset_for_new_entry()

        "hs_letter_index":
            _letter_index = int(value)
            _timer_remaining = TIMER_SECONDS  # reset timer on navigation
            _update_carousel()

        "hs_select_trigger":
            var new_trigger = int(value)
            # 0 = MPF reset the counter for a new entry - not a button press
            if new_trigger <= 0:
                _select_trigger = 0
                return
            if new_trigger > _select_trigger and _active and not _submitted:
                _select_trigger = new_trigger
                _timer_remaining = TIMER_SECONDS
                _handle_select()

func _handle_select() -> void:
    var ch = CHAR_VALUES[_letter_index]
    match ch:
        "FINISH":
            _submit_name()
        "BACK":
            if _typed_name.length() > 0:
                _typed_name = _typed_name.left(_typed_name.length() - 1)
            _update_name_display()
        _:
            if _typed_name.length() < MAX_NAME_LENGTH:
                _typed_name += ch
                _update_name_display()
            if _typed_name.length() >= MAX_NAME_LENGTH:
                # Tell MPF to jump carousel to FINISH position
                MPF.server.send_event("hs_name_full")

func _submit_name() -> void:
    if _submitted:
        return
    _submitted = true
    _active    = false
    var final_name = _typed_name.strip_edges()
    if final_name.is_empty():
        final_name = "LFS"
    MPF.server.send_event_with_args("text_input_high_score_complete", {"text": final_name})

func _update_carousel() -> void:
    var prev_idx = (_letter_index - 1 + TOTAL_CHARS) % TOTAL_CHARS
    var next_idx = (_letter_index + 1) % TOTAL_CHARS
    var p = get_parent()
    if p.has_node("CarouselPrev"):    p.get_node("CarouselPrev").text    = CHAR_DISPLAY[prev_idx]
    if p.has_node("CarouselCurrent"): p.get_node("CarouselCurrent").text = CHAR_DISPLAY[_letter_index]
    if p.has_node("CarouselNext"):    p.get_node("CarouselNext").text    = CHAR_DISPLAY[next_idx]

func _update_name_display() -> void:
    var p = get_parent()
    if p.has_node("NameDisplay"):
        p.get_node("NameDisplay").text = _typed_name + "_"

func _update_timer_display() -> void:
    var p = get_parent()
    if p.has_node("TimerLabel"):
        p.get_node("TimerLabel").text = str(ceili(_timer_remaining))
