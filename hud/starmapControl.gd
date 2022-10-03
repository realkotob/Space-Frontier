extends Control


# Declare member variables here. Examples:
var src = null
var tg = null

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func get_src_loc():
	return src.get_node("PlanetTexture").get_global_position()
	
	#var loc = src.rect_position
	#loc = loc + src.get_node("PlanetTexture").rect_position
	#return loc
	
func get_tg_loc():
	return tg.get_node("PlanetTexture").get_global_position()
	#var loc = tg.rect_position
	#loc = loc + tg.get_node("PlanetTexture").rect_position
	#return loc
	
func get_tg():
	var tg = null
	for c in get_children():
		if "selected" in c and c.selected:
			tg = c
			break
	return tg