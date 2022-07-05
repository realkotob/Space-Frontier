extends Control

const LY_TO_PX = 50;
export var x = 0.0
export var y = 0.0
export var depth = 0.0
export var named = ""

# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	# positioning the stuff
	# in Godot, +Y goes down so we need to minus the Y we get from data
	set_position(Vector2(x*LY_TO_PX, -y*LY_TO_PX))
	
	# positive depth (above the plane) is negative y
	var ab = (y*LY_TO_PX - depth*LY_TO_PX)
	var end = -depth*LY_TO_PX
	# snap to panel top
	# the panel is 525px tall so it fits 50px ten times
	if ab < -400:
		print("Snapping to panel for ", get_name())
		# so that we don't go out of panel
		end = -200 - y*LY_TO_PX
		#print("End: ", end)

	get_node("Line2D").points[0] = Vector2(18, end)
	
	
	var depth_s = sign(-depth)
	# 18 is the height of the star icon
	get_node("TextureRect3").rect_position = Vector2(0, end+18*depth_s) 
	# name label
	# above the plane (place next to star icon)
	if depth_s < 0:
		get_node("Label").rect_position = Vector2(-6.5, end+18)
	# below the plane (place next to "shadow" icon)
	else:
		get_node("Label").rect_position = Vector2(0, 0)
	
	# Z axis label if needed
	if abs(depth) > 8:
		# above the plane (place next to star icon)
		if depth_s < 0:
			get_node("Label2").rect_position = Vector2(-6.5, end+32)	
		else:
			# place next to shadow icon for below the plane
			get_node("Label2").rect_position = Vector2(0, 25)
		get_node("Label2").set_text("Z: " + str(depth) + " ly")
		get_node("Label2").show()
	
	set_name(named)
	get_node("Label").set_text(named)


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
