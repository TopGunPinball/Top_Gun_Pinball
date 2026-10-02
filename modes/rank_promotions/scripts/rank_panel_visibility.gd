extends MPFVariable
## Shows/hides the rank panel (rank_promotions). Linked to player var
## rank_panel_hidden: 1 while 2X or a pilot/training/hard deck mission is
## running (those use this part of the screen), 0 otherwise. Draws nothing
## itself. The player-box rank icons are NOT in targets - they never hide.

@export var targets: Array[NodePath] = []

func update_text(value) -> void:
	var hide_it := false
	if value is int or value is float:
		hide_it = int(value) == 1
	for t in targets:
		var n = get_node_or_null(t)
		if n is CanvasItem:
			n.visible = not hide_it
	text = ""
