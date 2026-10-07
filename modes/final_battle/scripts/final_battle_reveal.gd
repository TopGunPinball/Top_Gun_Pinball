extends MPFVariable
## Shows its targets once the linked number reaches `threshold`
## (tally rows, perk lines). Draws nothing itself.

@export var threshold: int = 1
@export var targets: Array[NodePath] = []

func update_text(value) -> void:
	var v := 0
	if value is int or value is float:
		v = int(value)
	elif value is String and value.is_valid_int():
		v = value.to_int()
	for t in targets:
		var n = get_node_or_null(t)
		if n is CanvasItem:
			n.visible = v >= threshold
	text = ""
