extends Area2D

# class member variables go here, for example:
export var rot_speed = 2.6 #radians
export var thrust = 500
export var max_vel = 400
export var friction = 0.65

# motion
var rot = 0
var pos = Vector2()
var vel = Vector2()
var acc = Vector2()

# bullets
export(PackedScene) var bullet
onready var bullet_container = $"bullet_container"
#onready var bullet = preload("res://bullet.tscn")
onready var gun_timer = $"gun_timer"
onready var explosion = preload("res://explosion.tscn")

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	pass

# using this because we don't need physics
func _process(delta):
#	# Called every frame. Delta is time since last frame.
#	# Update game logic here.

	# shoot
	if Input.is_action_pressed("ui_select"):
		if gun_timer.get_time_left() == 0:
			shoot()

	# rotations
	if Input.is_action_pressed("ui_left"):
		rot -= rot_speed*delta
	if Input.is_action_pressed("ui_right"):
		rot += rot_speed*delta
	# thrust
	if Input.is_action_pressed("ui_up"):
		acc = Vector2(0, -thrust).rotated(rot)
	else:
		acc = Vector2(0,0)
	
	
	# movement happens!
	acc += vel * -friction
	vel += acc *delta
	pos += vel * delta
	set_position(pos)
	# rotation
	set_rotation(rot)

func shoot():
	gun_timer.start()
	var b = bullet.instance()
	bullet_container.add_child(b)
	b.start_at(get_rotation(), $"muzzle".get_global_position())