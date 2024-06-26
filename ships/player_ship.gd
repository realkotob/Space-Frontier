extends "ship_basic.gd"

# class member variables go here, for example:
var shield_level = 1
var engine_level = 1
var power_level = 1
signal module_level_changed

var shoot_power_draw = 10
var warp_power_draw = 50
var power_recharge = 5

var engine = 1000 # in reality, it represents fuel, call it engine for simplicity
var engine_draw = 50 # how fast our engine wears out when boosting
signal engine_changed
var boost = false
var scooping = false

var has_cloak = false
var cloaked = false
var has_tractor = true

#onready var warp_effect = preload("res://warp_effect.tscn")
#onready var warp_timer = $"warp_correct_timer"

@onready var recharge_timer = $"recharge_timer"

var target = null
# warp drive
var heading = null
var warp_planet
#var warp_target = null
var cruise = false
var distress_caller = null

var auto_orbit = false
var planet_to_orbit = null
var auto_cruise_tg = null

var tractored = false
var refit_target = false

var targeted_by = []

var HUD = null
signal officer_message

@export var has_armor = false
var armor = 50
signal armor_changed

var credits = 0
var kills = 0
var points = 0
signal kill_gained
signal points_gained

var landed = false
var can_land = true
signal planet_landed

# for AI orders
var conquer_target = null

# player only
var w_hole = null
var route = null
var disrupted = false
var dead = false
var god = true

# better ships
enum ship_class {SCOUT, FREIGHTER, DESTROYER}
@export var class_id: int = 0
var scout = load("res://ships/player_ship.tscn")
var freighter = load("res://ships/player_ship_freighter.tscn")
var destroyer = load("res://ships/player_ship_destroyer.tscn")

func welcome():
	# give start date
	var msg = "Welcome to the space frontier! The date is %02d-%02d-%d" % [game.start_date[0], game.start_date[1], game.start_date[2]]
	emit_signal("officer_message", msg, 5.0);

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	game.player = self
	#get_parent().set_z_index(game.PLAYER_Z)
	set_z_index(game.PLAYER_Z)
	get_parent().add_to_group("player")
	
	var _conn = connect("shield_changed",Callable(self,"_on_shield_changed"))
	
	if not has_armor:
		armor = 0
		#hiding HUD in HUD.gd
	else:
		# armor makes us heavier (=slows down)
		max_vel = 0.35 * LIGHT_SPEED
		thrust = 0.1 * LIGHT_SPEED
		
		
	# godmode confers cloak
	if god:
		has_cloak = true

func spawn():
	# spawn somewhere interesting
	var planet = get_tree().get_nodes_in_group("planets")[0]
	
	if get_tree().get_nodes_in_group("planets").size() > 3: 
		planet = get_tree().get_nodes_in_group("planets")[2] #2 Earth # 11 Neptune
	print("Location of planet " + str(planet) + " : " + str(planet.get_global_position()))
	
	# fudge
	var offset = Vector2(0,0) #Vector2(50,50)
	get_parent().set_global_position(planet.get_global_position() + offset)
	set_position(Vector2(0,0))
	
	call_deferred("welcome")
	
#----------------------------------
# input (spread across process and fixed_process)
# using this instead of fixed_process because we don't need physics
func _process(delta):
	# skip iter if dead
	if dead:
		return
	
	
#	# Called every frame. Delta is time since last frame.
#	# Update game logic here.
	# were we boosting last tick?
	var old_boost = boost 

	# redraw 
	queue_redraw()

	# measured in fractions of light speed (x.xx c)
	spd = vel.length() / LIGHT_SPEED
	boost = false
	
	$engine_flare.process_material.color = get_engine_exhaust_color()

	#if Input.is_action_pressed("space"):
	#	print("Space pressed")

	# shoot
	if Input.is_action_pressed("shoot"):
		if gun_timer.get_time_left() == 0 and not landed:
			shoot()
		else:
			emit_signal("officer_message", "Guns not ready yet!")

	# tractor
	if tractor:
		var dist = get_global_position().distance_to(tractor.get_child(0).get_global_position())
		
		# too far away, deactivate
		if dist > 100:
			tractor.get_child(0).tractor = null
			tractor = null
			print("Deactivating tractor")
			
		else:
			#print("Tractor active on: " + str(tractor.get_name()) + " " + str(dist))
			tractor.get_child(0).tractor = self

	# upgrade
	if Input.is_action_just_pressed("upgrade"):
		# don't upgrade if cargo screen open
		if docked:
			if not game.player.HUD.get_node("Control2/Panel_rightHUD/PanelInfo/CargoInfo").is_visible():
				#print("Trying to upgrade...")
				# upgrade the ship!
				upgrade_ship()
				# new ship has to be docked, too
				game.player.dock()
				game.player.HUD.get_node("Control2").update_ship_name()
				return
			else:
				# sell stuff
				game.player.HUD.get_node("Control2")._onButtonSell_pressed()
			
	# camera
	# just_pressed means it does it in steps, like the original game did
	if Input.is_action_just_pressed("zoom_in"):
		var cam = get_node("Camera2D")
		if cam.zoom.x > 0.5:
			cam.zoom.x = cam.zoom.x - 0.1
			cam.zoom.y = cam.zoom.y - 0.1
		# keep the shield indicator roughly the same apparent size when zoomed in
		if cam.zoom.x < 1:
			var val = abs(cam.zoom.x-1)
			var sc = lerp(1, 0.5, val)
			#print("lerp: ", val, " sc: ", sc)
			get_node("shield_indicator").set_scale(Vector2(sc, sc))
		else:
			get_node("shield_indicator").set_scale(Vector2(1,1))
		
		
	if Input.is_action_just_pressed("zoom_out"):
		var cam = get_node("Camera2D")
		if cam.zoom.x < 1.5:
			cam.zoom.x = cam.zoom.x + 0.1
			cam.zoom.y = cam.zoom.y + 0.1 
		# keep the shield indicator roughly the same apparent size when zoomed in
		if cam.zoom.x < 1:
			var val = abs(cam.zoom.x-1)
			var sc = lerp(1, 0.5, val)
			get_node("shield_indicator").set_scale(Vector2(sc, sc))
		else:
			get_node("shield_indicator").set_scale(Vector2(1,1))	
		
		
	# rotations
	if Input.is_action_pressed("move_left"):
		if warping == false:
			rot -= rot_speed*delta
	if Input.is_action_pressed("move_right"):
		if warping == false:
			rot += rot_speed*delta
	
	if Input.is_action_pressed("move_down"):
		if orbiting:
			deorbit()
		
		if auto_orbit:
			auto_orbit = false
			
		if cruise:
			warp_target = null
			cruise = false
	
	# thrust
	if Input.is_action_pressed("move_up"):
		if auto_orbit:
			auto_orbit = false
		
		
		boost = true
		# QoL feature - launch
		if landed:
			launch()
		
		# undock
		if docked:
			# restore original z
			#get_parent().set_z_index(game.PLAYER_Z)
			set_z_index(game.PLAYER_Z)
			docked = false
			# reparent
			var root = get_node("/root/Control")
			var gl = get_global_position()
					
			get_parent().get_parent().remove_child(get_parent())
			root.add_child(get_parent())
					
			get_parent().set_global_position(gl)
			set_position(Vector2(0,0))
			pos = Vector2(0,0)
					
			set_global_rotation(get_global_rotation())
		
		# deorbit
		if orbiting:
			deorbit()
		else:
			if not warping: #warp_target == null:
				acc = Vector2(0, -thrust).rotated(rot)
				$"engine_flare".set_emitting(true)
				# use up engine only if we changed boost
				#print("boost: " + str(boost) + "old: " + str(old_boost))
				if boost != old_boost:
					if engine > 0:
						engine = engine - engine_draw
						emit_signal("engine_changed", engine)
	
	# i.e. switch the booster on and keep it that way without player intervention
	elif cruise:
		boost = true
		# deorbit
		if orbiting:
			deorbit()
		else:
			acc = Vector2(0, -thrust).rotated(rot)
			$"engine_flare".set_emitting(true)
			# use up engine only if we changed boost
			if boost != old_boost:
				if engine > 0:
					engine = engine - engine_draw
					emit_signal("engine_changed", engine)
	else:
		acc = Vector2(0,0)
		$"engine_flare".set_emitting(false)
	
	# NOTE: actual movement happens here!
	if not orbiting:
		# movement happens!
		# modify acc by friction dependent on vel
		acc += vel * -friction
		vel += acc *delta
		# prevent exceeding max speed
		vel = vel.limit_length(max_vel)
		pos += vel * delta
		set_position(pos)
		#print("Setting position" + str(pos))
	
	if heading == null and auto_cruise_tg != null:
		player_autocruise(auto_cruise_tg, delta)
	
	# warp drive!
	if heading == null and warp_target != null:
		if warping:
			if warp_planet:
				# update target because the planet is orbiting, after all...
				warp_target = warp_planet.get_global_position()
			
			var desired = warp_target - get_global_position()
			var dist = desired.length()
			
			if dist > LIGHT_SPEED:
				vel = Vector2(0, -LIGHT_SPEED).rotated(rot)
				pos += vel* delta
				# prevent accumulating
				vel = vel.limit_length(LIGHT_SPEED)
				set_position(pos)
			else:
				# we've arrived, return to normal space
				warp_target = null
				warping = false
				cruise = false
				warp_timer.stop()
				# remove tint
				get_child(0).get_material().set_shader_parameter("modulate", Color(1,1,1))
			
	# refit
	if heading == null and refit_target:
		var desired = refit_target.get_global_position() - get_global_position()
		var dist = desired.length()
		
		desired = desired.normalized()
		if dist < 100:
			var m = remap(dist, 0, 100, 0, max_vel) 
			desired = desired * m
		else:
			desired = desired * max_vel
			tractored = false
			
		vel = desired.limit_length(max_vel)
		pos += vel*delta
		set_position(pos)
		
		if dist < 50 and not docked:
			# switch off cruise if any
			cruise = false
			
			# reparent			
			get_parent().get_parent().remove_child(get_parent())
			# refit target needs to be a node because here
			refit_target.add_child(get_parent())
			
			dock()
			
			# arrived
			refit_target = null
			#print("No refit target anymore")
			# disable tractor
			tractored = false
			#docked = true
			# officer message
			var msg = "Docking successful"
			if rank >= 2:
				msg = msg + ". Press backspace to upgrade your ship"
			emit_signal("officer_message", msg)
			# show refit screen
			self.HUD.switch_to_refit()
			
		elif dist < 80:
			tractored = true
			#print("We're being tractored in")
	
	# approach to orbit
	if auto_orbit and warp_target == null:
		if heading == null: #and cruise:
			var pl = get_closest_planet()
			
			# bug fix
			if pl[1] != planet_to_orbit:
				# abort if we approached something else!
				# stop warp timer
				warp_timer.stop()
				cruise = false
				heading = null
				auto_orbit = false
				planet_to_orbit = null
			
			if pl[0] > 200*pl[1].planet_rad_factor and pl[0] < 300*pl[1].planet_rad_factor:
				# stop warp timer
				warp_timer.stop()
				# auto-orbit
				player_orbit(pl)
			
	# rotation
	# handling heading (usually the warp-drive)
	if heading:
		player_heading(heading, delta)
			
			
		
	set_rotation(rot)
	
	# fix jitter due to camera updating one frame late
	get_node("Camera2D").align()
	
	# overheat damage
	if is_overheating():
		get_child(0).get_material().set_shader_parameter("swizzle_type", 1)
		#print("distance to star: " + str(dist))
		if get_node("heat_timer").get_time_left() == 0:
			heat_damage()
	else:
		get_child(0).get_material().set_shader_parameter("swizzle_type", 0)

	# target direction indicator
	if HUD.target != null and is_instance_valid(HUD.target) and HUD.target != self:
		get_node("target_dir").show()
		var tg_rel_pos = HUD.target.get_global_position() * get_global_transform() 
		get_node("target_dir").set_position(tg_rel_pos.limit_length(60))
		# point at the target
		#var a = atan2(tg_rel_pos.x, tg_rel_pos.y)
		var a = fix_atan(tg_rel_pos.x, tg_rel_pos.y)
		#var angle_to = (-a+3.141593)
		get_node("target_dir").set_rotation(-a)

	
# those functions that need physics
func _input(_event):
	# skip iter if dead
	if dead:
		return
		
	# don't listen to individual keybinds if starmap view open
	if self.HUD.get_node("Control4/star map").is_visible():
		return
	
	# mouse to steer
	if _event is InputEventMouseButton:
		if _event.is_pressed() and _event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			print("Clicked @ ", _event.position, " ", _event.global_position)
			# ignore clicks on sidebar
			if _event.position.x > 940:
				return
				
			# this is where the player ship is, see comment in HUD.gd line 337
			var cntr = Vector2(1024*self.HUD.viewport_factor.x/2, 300*self.HUD.viewport_factor.y)	
			#print("cntr: ", cntr)
			heading = _event.position-cntr  # heading is global
			#print("Local heading: ", heading)
			heading = to_global(heading)
			print("Global heading: ", heading)
			auto_cruise_tg = heading
	
	if Input.is_action_pressed("closest_target"):
		get_closest_target()
	
	if Input.is_action_pressed("closest_friendly_target"):
		get_closest_friendly_target()
	
	if Input.is_action_pressed("join"):
		# can't pick up colonies if we don't have the tractor/dock module
		if not has_tractor:
			return
		
		if not orbiting:
			print("Not orbiting")
		else:
			if get_colony_in_dock() == null:
				var col = pick_colony()
				if col:
					emit_signal("officer_message", "We have picked up a colony. Transport it to a planet and press / to drop it.")
				else:
					print("Planet has too little pop to create colony")
			else:
				var added = add_to_colony()
				if added:
					emit_signal("officer_message", "We have picked up additional colonists.")
				
				
				
	if Input.is_action_pressed("orbit"):
		#print("Try to orbit")
		var pl = get_closest_planet()
		
		# does the planet have moons?
		if pl[1].has_moon():
			for m in pl[1].get_moons():
				# ignore moonlets (e.g. Phobos and Deimos)
				if m.mass < 0.00001 * game.MOON_MASS:
					continue
					
				var m_dist = m.get_global_position().distance_to(get_global_position())
				print("Moon distance " + str(m_dist))
				if m_dist < 50:
					print("Too close to orbit the moon")
				elif m_dist > 150:
					print("Too far away to orbit the moon")
				else:
					player_orbit([m_dist, m])
					return

		# values are eyeballed for current planets (scale 1, sprite 720*0.5=360 px)
		if pl[0] > 300*pl[1].planet_rad_factor:
			print("Too far away to orbit")
			# approach
			auto_orbit = true
			heading = pl[1].get_global_position()
			planet_to_orbit = pl[1] # remember what we want to orbit
			# if we are too close, don't fire the engines
			if pl[0] > 150:
				cruise = true
			# reuse the 1s warp timer
			warp_timer.start()
			
		elif pl[0] < 200*pl[1].planet_rad_factor:
			print("Too close to orbit")
			# TODO: head away from planet
		else:
			player_orbit(pl)
	
	if Input.is_action_pressed("refit"):
		print("Want to refit")
		
		var base = get_friendly_base()
		if not base:
			emit_signal("officer_message", "No friendly base found in system!")
			return
			
		heading = base.get_global_position()
		refit_target = base
	
	# tractor
	if Input.is_action_pressed("tractor"):
		# if no tractor module, abort
		if has_tractor == false:
			return
			
		# toggle
		if not tractor:
			var col = get_closest_floating_colony()
			if col != null:
				tractor = col
		else:
			tractor = null

	if Input.is_action_pressed("undock_tractor"):
		print("Undock pressed")
		
		tractor = null
	
		var col = get_colony_in_dock()
		if col:
			# set flag naming us as to be rewarded for colonizing
			col.get_child(0).to_reward = self
			print("[COLONY] To reward: " + str(col.get_child(0).to_reward))
			
			# undock
			remove_child(col)
			get_parent().get_parent().add_child(col)
			
			# restore original z
			col.set_z_index(0)
			
			col.set_global_position(get_node("dock").get_global_position() + Vector2(0, 20))
			
			#print("Undocked")
	
	# panel keybinds
	if Input.is_action_pressed("nav"):
		self.HUD.get_node("Control2").switch_to_navi()
	if Input.is_action_pressed("ship_view"):
		# switch to ship panel
		self.HUD._on_ButtonShip_pressed()
	if Input.is_action_pressed("players_list"):
		self.HUD.get_node("Control2")._onButtonCensus_pressed()
	if Input.is_action_pressed("help"):
		self.HUD.get_node("Control2").switch_to_help()
	if Input.is_action_pressed("cargo_panel"):
		self.HUD._on_ButtonCargo_pressed()
		#self.HUD.switch_to_cargo()
		
	if Input.is_action_pressed("go_planet"):
		# we hijack the same keybind to work for distress calls
		# because the caller might've been destroyed in the meantime
		if distress_caller != null and is_instance_valid(distress_caller):
			warp_target = distress_caller.get_global_position()
			heading = warp_target
			on_warping()
			return
		
		# no warping if we are hauling a colony
		# the check is in on_warping()
		# if already warping, abort
		if warping:
			print("Aborting q-drive...")
			warping = false
			warp_target = null
			heading = null
			warp_timer.stop()
			# remove tint
			get_child(0).get_material().set_shader_parameter("modulate", Color(1,1,1))
			return
		# if we have a planet view open, just act as a hotkey for "Go to"
		if self.HUD.get_node("Control2/Panel_rightHUD/PanelInfo/PlanetInfo").is_visible():
			# extract planet name from planet view
			var planet_name = self.HUD.planet_name_from_view()
			warp_planet = self.HUD.get_named_planet(planet_name)
			warp_target = warp_planet.get_global_position()
			heading = warp_target
			on_warping()
			return
		# if we have a warp planet already set, go to it
		if warp_planet and not warping:
			warp_target = warp_planet.get_global_position()
			heading = warp_target
			on_warping()
			return

	if Input.is_action_pressed("landing"):
		if not can_land:
			return
		if not landed:
			var pl = get_closest_planet()
			# values are eyeballed for current planets
			if pl[0] < 200:
				#print("Can land")
				print("Landing...")
				$"shield_indicator".hide()
				get_parent().get_node("AnimationPlayer").play("landing")
				# landing happens only when the animation is done
				# prevents too fast landings
				can_land = false
				# reparent
				get_parent().get_parent().remove_child(get_parent())
				pl[1].get_node("orbit_holder").add_child(get_parent())
				get_parent().set_position(Vector2(0,0))
				set_position(Vector2(0,0))
				pos = Vector2(0,0)
				# nuke velocities
				acc = Vector2(0,0)
				vel = Vector2(0,0)
				# start the timer
				$landing_timeout.start()
			else:
				print("Too far away to land")
		else:
			launch()
	
	# hack fix: don't engage cloak if cargo view open
	if Input.is_action_pressed("cloak") and not HUD.get_node("Control2/Panel_rightHUD/PanelInfo/CargoInfo").is_visible():
		if has_cloak:
			# toggle
			cloaked = not cloaked
			if cloaked:
				# sprite overlay only!
				get_child(1).set_modulate(Color(0.3, 0.3, 0.3))
				$playerShip3_overlay.show()
			else:
				get_child(1).set_modulate(Color(1,1,1))
				$playerShip3_overlay.hide()

	if Input.is_action_pressed("scan"):
		if HUD.target != null and HUD.target != self:
			if 'scanned' in HUD.target:
				if scan(HUD.target):
					# reward points
					points += 3
					emit_signal("points_gained", points)
					# rank up if we exceeded a multiple of 10!
					if points > 10 and points % 10 > 0:
						rank = rank + 1
			


# -------------------------
func enable_cam():
	game.player.get_node("Camera2D").set_current(true)
	game.player.get_node("Camera2D").align()

func upgrade_ship():
	var ship = scout.instantiate() # the default
	if class_id < 1:
		ship = freighter.instantiate()
		# set armor
		has_armor = true
		armor = 50
		# armor makes us heavier (=slows down)
		max_vel = 0.35 * LIGHT_SPEED
		thrust = 0.1 * LIGHT_SPEED
	
	if self.rank > game.ranks.SCLT: 
		ship = destroyer.instantiate()
	
	var old_HUD = HUD
	#print(old_HUD.get_name())
	get_parent().get_parent().add_child(ship)

	#update all the refs			
	# we need the Area2D, not the topmost node
	game.player = ship.get_child(0)
	game.player.HUD = old_HUD
	HUD.player = game.player
	HUD.get_node("Control2").player = game.player
	HUD.connect_player_signals(game.player)
	HUD.toggle_armor_label()
	HUD.update_panel_sprite()
	var mmap = get_tree().get_nodes_in_group("minimap")[0]
	mmap.player = game.player
	
	# make the transition less jarring by hiding 
	# TODO: a flashy effect here
	get_parent().hide()
	get_node("Camera2D").set_current(false)

	# remove the old ship
	get_parent().queue_free()
	
	ship.set_name("player")
	
	# fix the camera jank by deferring active camera change
	call_deferred("enable_cam")

func dock():
	docked = true
	# set better z so that we don't overlap parent ship
	set_z_index(-1)
	#set_z_index(game.BASE_Z-1)
	
	# nuke any velocity left
	vel = Vector2(0,0)
	acc = Vector2(0,0)
	
	var friend_docked = false
	# get_parent().get_parent() is the refit_target/starbase
	# 7 is the default, so only check if we have more
	if get_parent().get_parent().get_child_count() > 7:
		for ch in get_parent().get_parent().get_children():
			if ch is Node2D and ch.get_index() > 6:
				if ch.get_child_count() > 0 and ch.get_child(0).is_in_group("friendly") and not ch.get_child(0).is_in_group("drone"):
#							print(ch.get_child(0).get_name())
#							print(str(ch.get_child(0).is_in_group("friendly")))
					print("Friendly docked with the starbase")
					friend_docked = true
					break
	
	# all local positions relative to the immediate parent
	if friend_docked:
		get_parent().set_position(Vector2(-25,50))
	else:
		if get_parent().get_parent().get_name().find("cycler"):
			get_parent().set_position(Vector2(25, 50))
		else:
			get_parent().set_position(Vector2(0,50))
	set_position(Vector2(0,0))
	pos = Vector2(0,0)
	
	#print("Adding player as tractoring ship's child")

func _on_AnimationPlayer_animation_finished(_anim_name):
	#print("Animation finished")
	# toggle the landing state
	if not landed:
		landed = true
		emit_signal("planet_landed")
		emit_signal("officer_message", "Landed on a planet. Fuel replenished")
		# fill up the engine/fuel
		engine = 1000 
	else:
		landed = false

#	#var hide = not $"shield_indicator".is_visible()
#	if not $"shield_indicator".is_visible():
#		$"shield_indicator".show()

func launch():
	get_parent().get_node("AnimationPlayer").play_backwards("landing")
	$"shield_indicator".show()
	# prevent too fast landings
	can_land = false
	# reparent
	var root = get_node("/root/Control")
	var gl = get_global_position()
			
	get_parent().get_parent().remove_child(get_parent())
	root.add_child(get_parent())
			
	get_parent().set_global_position(gl)
	set_position(Vector2(0,0))
	pos = Vector2(0,0)
			
	set_global_rotation(get_global_rotation())
	
	on_launch()
	
func on_launch():
	# close cargo view if open
	if HUD.get_node("Control2/Panel_rightHUD/PanelInfo/CargoInfo").is_visible():
		HUD.get_node("Control2/Panel_rightHUD/PanelInfo/CargoInfo").hide()
	

func _on_landing_timeout_timeout():
	can_land = true

func player_autocruise(target, delta):
	var rel_pos = target * get_global_transform()
	print("Heading rel_pos", rel_pos)

	# disable cruise if too close, to avoid overshooting close targets
	if rel_pos.length() < 150 and spd > 0.15:
		cruise = false
		auto_cruise_tg = null # and shut ourselves off
		heading = null
	else:
		cruise = true

func player_heading(target, delta):
	var rel_pos = target * get_global_transform()
	print("Heading rel_pos", rel_pos)
	
	var a = atan2(rel_pos.x, rel_pos.y)
	
#	# disable cruise if any
#	if cruise:
#		cruise = false
	
	# we've turned to face the target
	if abs(rad_to_deg(a)) > 179:
		#on_heading()
		#print("Achieved target heading")
		heading = null
		if auto_cruise_tg == null:
			# reset cruise
			cruise = true
		# disable cruise if too close, to avoid overshooting close targets
		if rel_pos.length() < 150 and spd > 0.15:
			cruise = false
	
	if a < 0:
		rot -= rot_speed*delta
	else:
		rot += rot_speed*delta

func player_orbit(pl):
	print("Can orbit")
	# cancel cruise if any
	if cruise:
		cruise = false
		
	if auto_orbit:
		auto_orbit = false
	
	if pl[1].has_node("orbit_holder"):
		orbit_planet(pl[1])
		
		var txt = "Orbit established."
		if pl[1].has_colony():
			txt += " Fuel replenished. Press J to request a colony"
			# fill up the engine/fuel
			engine = 1000 
			# restore power
			power = 100
			# restore some shields
			if shields < 50:
				shields = 50
		
		emit_signal("officer_message", txt)


func get_num_guns():
	var num = 0
	for c in get_children():
		if c.is_in_group("muzzle"):
			num = num + 1
	return num

func get_guns():
	var guns = []
	for c in get_children():
		if c.is_in_group("muzzle"):
			guns.append(c)
	return guns

# this one shoots *ALL* the guns/tubes/muzzles/whatever you want to call them	
func shoot():
	if warping:
		return
	
	var num = get_num_guns()
	var draw = shoot_power_draw*num
	#print("Num guns: ", num, " pwr draw: ", draw, " pwr: ", power)
	
	if power <= draw:
		emit_signal("officer_message", "Weapons systems offline!")
		return
		
	power -= draw
	emit_signal("power_changed", power)
	recharge_timer.start()
	
	# a single timer for now
	gun_timer.start()
	for g in get_guns():
		var b = bullet.instantiate()
		bullet_container.add_child(b)
		b.start_at(get_global_rotation(), g.get_global_position())

	
func scan(planet):
	if not planet.scanned:
		var msg = "Scanning planet " + str(planet.get_node("Label").get_text())
		emit_signal("officer_message", msg)
		if planet.has_node("AnimationPlayer"):
			planet.toggle_shadow_anim()
			planet.get_node("AnimationPlayer").play("scanning")
		planet.scanned = true
		# update planet view if open
		HUD.update_planet_view(planet)
		return true
	else:
		emit_signal("officer_message", "Already scanned planet.")
		return false
		
# ---------------------
func get_closest_planet():
	var planets = get_tree().get_nodes_in_group("planets")
	
	var dists = []
	var targs = [] # otherwise we have no way of knowing which planet the dist refers to
	
	for p in planets:
		var dist = p.get_global_position().distance_to(get_global_position())
		dists.append(dist)
		targs.append([dist, p])
		
	dists.sort()
	
	for t in targs:
		if t[0] == dists[0]:
			print("Closest planet is: " + t[1].get_name() + " at " + str(t[0]))
			return t

func get_closest_target():
	var t = get_closest_enemy()
	# paranoia
	if t != null:
		#t[1].targetted = true
		t.emit_signal("AI_targeted", t)
		# redraw 
		t.queue_redraw()
		# redraw minimap
		self.HUD._minimap_update_outline(t)

func get_closest_friendly_target():
	var t = get_closest_friendly()
	# paranoia
	if t != null:
		t.emit_signal("AI_targeted", t)
		# redraw 
		t.queue_redraw()
		# redraw minimap
		self.HUD._minimap_update_outline(t)

func _draw():
	if not warping and not disrupted:
		# distance indicator at a distance of 100 from the nosetip
		draw_line(Vector2(10, -100),Vector2(-10, -100),Color(1,1,0),4.0)
		
		# weapon range indicator
		var rang = 1000 * 0.25 # 1000 is the bullet's speed, 0.25 is the bullet's lifetime
		draw_line(Vector2(10, -rang),Vector2(-10, -rang),Color(1,0,0),4.0)
	
	# draw a red rectangle around the target
	if target == self:
		var rect = Rect2(Vector2(-35, -25),	Vector2(112*0.6, 75*0.6)) 
		
		draw_rect(rect, Color(1,0,0), false)
	else:
		pass
	
	if tractored:
		var tr = get_child(0)
		var rc_h = tr.get_texture().get_height() * tr.get_scale().x
		var rc_w = tr.get_texture().get_height() * tr.get_scale().y
		#var rect = Rect2(Vector2(-rc_w/2, -rc_h/2), Vector2(rc_w, rc_h))
		#draw_rect(rect, Color(1,1,0), false)
		
		# better looking effect
		var rel_pos = refit_target.get_global_position() * get_global_transform() 
		draw_line(rel_pos, Vector2(-rc_w/2, -rc_h/2), Color(1,1,0))
		draw_line(rel_pos, Vector2(rc_w/2, rc_h/2), Color(1,1,0))
		draw_line(rel_pos, Vector2(rc_w/2, -rc_h/2), Color(1,1,0))
		draw_line(rel_pos, Vector2(-rc_w/2, rc_h/2), Color(1,1,0))
		
	else:
		pass

func _on_shield_changed(data):
	var effect
	if data.size() > 1:
		effect = data[1]
	else:
		effect = true
	if effect:
		# generic effect
		$"shield_effect".show()
		$"shield_timer".start()
	
	# player-specific shield indicator
	if shields < 0.2 * 100:
		$"shield_indicator".set_modulate(Color(0.35, 0.0, 0.0)) #dark red
	elif shields < 0.5 * 100:
		$"shield_indicator".set_modulate(Color(1.0, 0.0, 0.0))
	elif shields < 0.7* 100: #current max
		$"shield_indicator".set_modulate(Color(1.0, 1.0, 0.0))
	else:
		$"shield_indicator".set_modulate(Color(0.0, 1.0, 0.0))

func _on_shield_timer_timeout():
	$"shield_effect".hide()



func heat_damage():
	shields = shields - 5
	emit_signal("shield_changed", [shields, false])
	get_node("heat_timer").start()


	

# click to target functionality
func _on_Area2D_input_event(_viewport, event, _shape_idx):
	# any mouse click
	if event is InputEventMouseButton and event.pressed:
		#target = self
		# redraw 
		queue_redraw()

func _on_goto_pressed(planet):
	print("Want to go to planet " + str(planet.get_name()))
	warp_planet = planet
	warp_target = planet.get_global_position()
	heading = warp_target
	on_warping()

func _on_scan_pressed(planet):	
	if scan(planet):
		# reward points
		points += 3
		emit_signal("points_gained", points)
		# rank up if we exceeded a multiple of 10!
		if points > 0 and points % 10 == 0:
			rank = rank + 1
	
func on_warping():
	if orbiting:
		deorbit()
	# if we somehow are flagged as cruising already, disable it
	if cruise:
		cruise = false
	
	# no warping if we are hauling a colony
	if get_colony_in_dock() != null:
		emit_signal("officer_message", "Too heavy to engage Q-drive, engaging cruise mode instead")
		cruise = true
		return
	
	if power < warp_power_draw:
		emit_signal("officer_message", "Insufficient power for Q-drive")
		return
		
	# are we far enough away?
	var desired = warp_target - get_global_position()
	var dist = desired.length()
			
	if dist < LIGHT_SPEED:
		emit_signal("officer_message", "Too close to target to engage Q-drive")
		return
		
		
	power -= warp_power_draw
	emit_signal("power_changed", power)
	recharge_timer.start()
	warp_timer.start()
	
	# effect
	var warp = warp_effect.instantiate()
	add_child(warp)
	warp.set_position(Vector2(0,0))
	warp.play()
	
	# tint a matching orange color
	# modulate affects child CanvasItems, too
	# we can't tint the sprite itself, need to pass to a shader
	get_child(0).get_material().set_shader_parameter("modulate", Color(1, 0.73, 0))

# update target and heading because the planet is orbiting, after all...
func _on_warp_correct_timer_timeout():
	if warping:
		warp_target = warp_planet.get_global_position()
		heading = warp_target
		warp_timer.start()
	# reuse the timer for approaching the closest planet
	elif auto_orbit:
		var pl = get_closest_planet()
		heading = pl[1].get_global_position()
		if not orbiting:
			warp_timer.start()

func _on_recharge_timer_timeout():
	#print("Power recharge...")
	# recharge
	if power < 100:
		power += power_recharge
		emit_signal("power_changed", power)

func _on_engine_timer_timeout():
	# give back a small amount of engine when we're not boosting it
	if engine < 1000:
		if can_scoop():
			print("Scooping...")
			self.HUD.get_node("AnimationPlayer").play("scooping")
			engine += 20
		if scooping:
			print("Scooping from gas giant...")
			self.HUD.get_node("AnimationPlayer").play("scooping")
			engine += 30 # because gas giant is more dense than a star's corona
		else:
			engine += 5
			
		emit_signal("engine_changed", engine)

	


func _on_conquer_pressed(id):
	print("Setting conquer target to: " + get_tree().get_nodes_in_group("planets")[id].get_node("Label").get_text())
	conquer_target = id+1 # to avoid problems with state's parameter being 0 (= null)


# ----------------------------
func refresh_cargo():
	if 'storage' in get_parent().get_parent():
		HUD.update_cargo_listing(cargo, get_parent().get_parent().storage)
		HUD.update_cargo_heading("Cargo storage for base")
	elif 'storage' in get_parent().get_parent().get_parent(): # planet
		HUD.update_cargo_listing(cargo, get_parent().get_parent().get_parent().storage)
		HUD.update_cargo_heading("Cargo storage for: " + get_parent().get_parent().get_parent().get_node("Label").get_text())
	
	else:
		HUD.update_cargo_listing(cargo)
		HUD.update_cargo_heading("Cargo storage")

func cargo_empty(cargo):
	var ret = false
	if cargo.size() < 1:
		ret = true
	else:
		ret = true
		for i in range(0, cargo.keys().size()):
			if cargo[cargo.keys()[i]] > 0:
				ret = false
	
	return ret

func sell_cargo(id):
	if not docked:
		print("We cannot sell if we're not docked")
		return false
	
	if not cargo.keys().size() > 0:
		return false
	
	# with starting inventory, the base should have the thing we want to sell
	# HUD.gd 886, we now display base storage so the id refers to base storage...
	var key = get_parent().get_parent().storage.keys()[id]
	#print(get_parent().get_parent().storage[get_parent().get_parent().storage.keys()[id]] > 0:
	print("Want to sell: " + key)
	
	if key in cargo and cargo[key] > 0:
		cargo[key] -= 1
		credits += 50
		# add cargo to starbase
		if not get_parent().get_parent().storage.has(key):
			get_parent().get_parent().storage[key] = 1
		else:
			get_parent().get_parent().storage[key] += 1
		HUD.update_cargo_listing(cargo, get_parent().get_parent().storage)
		return true
	else:
		return false

func buy_cargo(id):
	if not docked:
		print("We cannot buy if we're not docked")
		return false
	
	if not get_parent().get_parent().storage.keys().size() > 0:
		return false
	
	
	if get_parent().get_parent().storage[get_parent().get_parent().storage.keys()[id]] > 0:
		get_parent().get_parent().storage[get_parent().get_parent().storage.keys()[id]] -= 1
		credits -= 50
		# add cargo to player
		if not cargo.has(get_parent().get_parent().storage.keys()[id]):
			cargo[get_parent().get_parent().storage.keys()[id]] = 1
		else:
			cargo[get_parent().get_parent().storage.keys()[id]] += 1
		HUD.update_cargo_listing(cargo, get_parent().get_parent().storage)	
		return true
	else:
		return false

# atan2(0,-1) returns 180 degrees in 3.0, we want 0
# this counts in radians
func fix_atan(x,y):
	var ret = 0
	var at = atan2(x,y)

	if at > 0:
		ret = at - PI
	else:
		ret= at + PI
	
	return ret
