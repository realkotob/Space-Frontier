extends Area2D

# class member variables go here, for example:
var vel = Vector2()
export var speed = 1000

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	pass

func _physics_process(delta):
	set_position(get_position() + vel * delta)

func start_at(dir, pos):
	# bullet's pointing to the side by default while the ship's pointing up
	set_rotation(dir-PI/2)
	set_position(pos)
	# pointing up by default
	vel = Vector2(0,-speed).rotated(dir)

func _on_lifetime_timeout():
	queue_free()
	
func _on_bullet_area_entered( area ):
	if area.get_groups().has("enemy"):
		queue_free()
		#print(area.get_parent().get_name())
		
		var pos = area.get_global_position()
		
		# notify AI - it has been attacked
		area.emit_signal("AI_hit", get_parent().get_parent())
		
		# go through armor first
		if 'armor' in area and area.armor > 0:
			area.armor -= 5 # armor absorbs some of the damage
			area.emit_signal("armor_changed", area.armor)
		else:
			area.shields -= 10
			# emit signal
			area.emit_signal("shield_changed", [area.shields])
		
		var sb = area.is_in_group("starbase")
		if sb:
			area.emit_signal("distress_called", get_parent().get_parent())
		
		
		if area.shields <= 0:
			# status light update
			if 'targeted_by' in get_parent().get_parent():
				print("Update status light on AI death")
				var find = get_parent().get_parent().targeted_by.find(area)
				if find != -1:
					get_parent().get_parent().targeted_by.remove(find)
				if get_parent().get_parent().targeted_by.size() < 1:
					area.emit_signal("target_lost_AI", area)			
			
			# mark is as no longer orbiting
			if area.orbiting != null:
				print("AI killed, no longer orbiting")
				area.orbiting.get_parent().remove_orbiter(area)
			
			# kill the AI
			area.get_parent().queue_free()

			# untarget it
			game.player.HUD.target = null
			# hide the target panel HUD
			game.player.HUD.hide_target_panel()

			# count a kill
			if 'kills' in get_parent().get_parent():
				get_parent().get_parent().kills = get_parent().get_parent().kills + 1
				get_parent().get_parent().emit_signal("kill_gained", get_parent().get_parent().kills)
				# credits
				get_parent().get_parent().credits = get_parent().get_parent().credits + 10000
				print("Cr: " + str(get_parent().get_parent().credits))
			
			# officer message for player
			if get_parent().get_parent() == game.player:
				game.player.emit_signal("officer_message", "Received kill credit of 10,000") # hardcoded amount for now
			
			# debris
			if "debris" in area:
				# do we get one at all?
				var chance = randf()
				if chance > 0.6:
					var deb = area.debris.instance()
					# randomize
					var sel = area.select_random_debris()
					deb.get_child(0).module = deb.get_child(0).match_string(sel)
					get_parent().get_parent().get_parent().add_child(deb)
					deb.set_global_position(pos)
				else:
					print("Not getting any debris")
			
			# explosion effect
			if "explosion" in get_parent().get_parent():
				var expl = get_parent().get_parent().explosion.instance()
				#print(get_parent().get_parent().get_parent().get_name())
				get_parent().get_parent().get_parent().add_child(expl)
				expl.set_global_position(pos)
				if sb:
					expl.set_scale(Vector2(2,2))
				else:
					expl.set_scale(Vector2(1,1))
				expl.play()
			

			
			# prevent hitting an asteroid in the same shot
			return
	
	if area.get_parent().get_groups().has("asteroid"):
		queue_free()
		
		#print(area.get_parent().get_name())
		
		var pos = area.get_global_position()
		
		# debris
		var deb = area.get_parent().resource_debris.instance()
		# randomize the resource
		deb.get_child(0).resource = area.get_parent().select_random()
		get_parent().get_parent().get_parent().add_child(deb)
		#print(get_parent().get_parent().get_parent().get_name())
		deb.set_global_position(pos)
		deb.set_scale(Vector2(0.5, 0.5))
		
		# explosion
		var expl = get_parent().get_parent().explosion.instance()
		get_parent().get_parent().get_parent().add_child(expl)
		expl.set_global_position(pos)
		expl.set_scale(Vector2(0.5, 0.5))
		expl.play()
		