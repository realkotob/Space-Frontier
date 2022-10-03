extends Control


# Declare member variables here. Examples:
var cntr = null
var clicked = false

# Called when the node enters the scene tree for the first time.
func _ready():
	cntr = $"../../Control"


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

# this is why this script even exists - to draw a line to target over everything else (e.g. the grid)
func _draw():
	# drawing a direction line
	var clr = Color(0,1,1) if not clicked else Color(1,0.5,0) # orange-red to match map icons and Z lines
	if cntr.tg:
		draw_line(cntr.src.get_node("PlanetTexture").rect_position+cntr.src.rect_position+cntr.rect_position, cntr.tg.rect_position+cntr.tg.get_node("PlanetTexture").rect_position+cntr.rect_position, clr, 3.0)