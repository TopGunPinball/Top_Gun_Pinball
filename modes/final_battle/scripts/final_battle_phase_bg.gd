extends MPFVariable
## Phase background switcher (final_battle_hud).
## Linked to player var fb_phase and shows the matching background:
##   1 = Canyon Run, 2 = Missiles, 3 = Old Relic, 4 = Bandits, 5 = Landing
## Anything else (intro 0, results 9) shows none. Draws nothing itself.
## Set each background's texture in the editor; an empty one just shows the
## plain center background.

@export var backgrounds: Array[NodePath] = []

func update_text(value) -> void:
	var phase := 0
	if value is int or value is float:
		phase = int(value)
	elif value is String and value.is_valid_int():
		phase = value.to_int()
	for i in backgrounds.size():
		var n = get_node_or_null(backgrounds[i])
		if n is CanvasItem:
			n.visible = (i + 1) == phase
	text = ""
