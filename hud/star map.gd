# map emulates the look of http://www.projectrho.com/public_html/rocket/images/spacemaps/RECONSmap.jpg
# the Z-lines are inspired by the so-called "hockey sticks" in Elite/Oolite
tool
extends "../galaxy.gd" #Control

# Declare member variables here. Examples:

var icon = preload("res://hud/star map icon.tscn")

const LY_TO_PX = 50;
var offset = Vector2(0,0)
var center = Vector2(382.5, 242.5) # experimentally determined
var grid = Vector2(0, -138) # experimentally determined

var systems = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	parse_data()
	get_node("../../Control2/Panel_rightHUD/Control/RouteHeightPanel").vis = get_node("Grid/VisControl")

# enum so we no longer have to remember the order the columns are in...
#enum col {NAME, WINCHELLX, WINCHELLY, WINCHELLZ, COLOR, PLANETS, MULTIPLE, COMMENTS, RA, DEC, DIST_SOL }
enum col {NAME, TYPE, RA, DEC, DIST_SOL, WINCHELLX, WINCHELLY, WINCHELLZ, MASS, RADIUS, ORBIT, LUMINOSITY, COLOR}
# it's here because we're saving data to our icons
func parse_data():
	data = load_data()
	
	systems = {}
	var ic = null

	#for line in data:
	for i in data.size():
		var line = data[i]
		#print(line)
		if line[col.NAME] != "Sol" and \
		line[col.TYPE].strip_edges() == "star" \
			and line[col.NAME].find(" B") == -1: # ignore B, C, etc. stars
			
			ic = icon.instance()
			# strip "A" etc.
			var _name = str(line[col.NAME])
			_name = _name.trim_suffix(" A")
			ic.named = _name
			
			#ic.named = str(line[0])
			if line[col.WINCHELLX] != " -":
				# strip units
				ic.x = strip_units(str(line[col.WINCHELLX]))
				#ic.x = float(line[1])
				ic.y = strip_units(str(line[col.WINCHELLY]))
				ic.depth = strip_units(str(line[col.WINCHELLZ]))
				ic.pos = float_to_int(Vector3(ic.x,ic.y,ic.depth))
				save_graph_data(ic.x, ic.y, ic.depth, ic.named)



			ic.star_type = str(line[col.COLOR]).strip_edges()
			# this only applies to known_systems_stars.csv
#			# does the star have planets?
#			ic.planets = false
#			if "yes" in line[col.PLANETS]:
#				ic.planets = true
#
#			if line.size() > 6:
#				if str(line[col.MULTIPLE]).strip_edges() == "double":
#					ic.multiple = line[col.MULTIPLE]
			
			# line[7] is for comments (col.COMMENTS)
			
			# ra-dec conversion
			if line[col.WINCHELLX] == " -": # and line.size() > 8 for old known_systems_stars.csv
				#print("RA/DEC candidate...")
				var ra = line[col.RA]
				var de = line[col.DEC] 
				if ra != "" and de != "" and line[col.DIST_SOL] != "":
					#print("RA/DEC convert for ", str(line[0]))
					var ra_deg = 0
					var dec = 0
					if "d" in ra:
						ra_deg = float(ra.rstrip("d"))
					if "deg" in ra:
						ra_deg = float(ra.rstrip("deg"))
					if "deg" in de:
						dec = float(de.rstrip("deg"))
					if "h" in ra and not "m" in ra:
						# if no minutes specified, we assume decimal hours
						# 15 degrees in an hour (360/24) 
						ra_deg = float(15*float(ra.rstrip("h")))
						# for now, assume degrees are given in decimal degrees
						dec = float(line[col.DEC])
					elif "h" in ra and "m" in ra:
						# http://voyages.sdss.org/preflight/locating-objects/ra-dec/
						# 0,25 (1/4) degree in a minute since it takes 4 minutes for a degree (60/15)
						var parts = ra.split("h")
						ra_deg = float(15*float(parts[0].rstrip("h")))
						ra_deg += float(0.25*float(parts[1].rstrip("m")))
					if "d" in de and "m" in de:
						var parts = de.split("d")
						dec = float(parts[0].rstrip("d"))
						dec += float(parts[1].rstrip("m"))/60
					if not "h" in ra:
						ra_deg = float(ra)
					if not "d" in de and not "m" in de:
						dec = float(de)
					
					var dist = float(line[col.DIST_SOL])
					if "pc" in line[col.DIST_SOL]:
						dist = strip_units(line[col.DIST_SOL])
					var data = galactic_from_ra_dec(ra_deg, dec, dist)
					# assign calculated values - no need to strip units as it's always
					ic.x = data[0]
					ic.y = data[1]
					ic.depth = data[2]
					ic.pos = float_to_int(Vector3(ic.x,ic.y,ic.depth))
					save_graph_data(ic.x, ic.y, ic.depth, ic.named)
			
			if abs(ic.depth) < 12:
				get_node("Control/Layer").add_child(ic)
			elif ic.depth > 12:
				get_node("Control/LayerZ+").add_child(ic)
			elif ic.depth < 12:
				get_node("Control/LayerZ-").add_child(ic)
			
			#get_node("Control").add_child(ic)
			
			# ------------------------------------
			# merged data only!
			#var star = line
			systems[_name] = []
			# append data necessary to create the system
			systems[_name].append([line[col.NAME], line[col.RADIUS], line[col.LUMINOSITY], ic.star_type])
			#print(systems, " after parsing the line ", line)

		# merged data files only!	
		# if a star but not A
		elif (line[col.TYPE].strip_edges() == "star" \
			#and line[col.NAME].find(" A") == -1) 
			and line[col.NAME].find(" B") != -1) \
			or line[col.TYPE].strip_edges() == "planet":
				#print("Not A star of a system: ", line)
				# because we ignore some systems (*cough cough* Sol)
				if systems.keys().size() > 0:
					var id = systems.keys().size()-1
					var _nam = systems.keys()[id]
					# append data necessary to create the system in main.gd
					var data = [line[col.NAME], line[col.TYPE], line[col.ORBIT], line[col.RADIUS]]
					if line[col.TYPE].strip_edges() == "star":
						data.append(line[col.LUMINOSITY])
						data.append(str(line[col.COLOR]).strip_edges())
					else:
						data.append(line[col.MASS])
					
					systems[_nam].append(data)
	
					# merged data only - new way of handling planets and multiple booleans
					if line[col.TYPE].strip_edges() == "star":
						ic.multiple = true
						# +1 because of ship /position marker
						#get_node("Control").get_child(get_node("Control").get_child_count()-1).multiple = true
					else:
						ic.planets = true
						#get_node("Control").get_child(get_node("Control").get_child_count()-1).planets = true
						# force update label text
						ic.add_planets_mark()
						#get_node("Control").get_child(get_node("Control").get_child_count()-1).add_planets_mark()

	# test
	#print(systems)
	
	# create a graph of stars we can route on
	var data = create_map_graph()
	
	# clearer debugging stuff
	get_node("Grid/VisControl").secondary = data[0]
	
	#var mst = data[1]
	#var tree = data[2]

	#for i in range(1, tree.size()-1):
	#	if !typeof(tree[i]) == TYPE_VECTOR3:
	#		continue # paranoia skip
		
		# for debugging
		#var connect = [find_icon_for_pos(mst[i-1]), find_icon_for_pos(tree[i])]
		#get_node("Grid/VisControl").secondary.append(connect)
		#get_node("Grid/VisControl").secondary.append()
		
#		map_astar.connect_points(mapping[mst[i-1]], mapping[tree[i]])
#
#		# we can use find_icon_for_pos here but we can't in the parent script
		#print("Connecting: ", find_icon_for_pos(mst[i-1]), " and ", find_icon_for_pos(tree[i]))

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

# -------------------------------------------------------------------------
func find_icon_for_pos(pos):
	var ret = null
	
	# special case
	if pos == Vector3(0,0,0):
		ret = $"Control/Layer".get_node("Sol")
		return ret
	
	var p
	if abs(pos.z) < 120:
		p = $"Control/Layer"
	elif pos.z > 120:
		p = $"Control/LayerZ+"
	elif pos.z < 120:
		p = $"Control/LayerZ-"
	
	for c in p.get_children():
		if 'pos' in c and c.pos == pos:
			ret = c
			break
	return ret

# returns icons!	
func get_neighbors_for_icon(star_icon):	
	var res = []
	var neighbors = null
	# paranoia
	if not "pos" in star_icon:
		neighbors = map_astar.get_point_connections(mapping[Vector3(0,0,0)])
	else:
		neighbors = map_astar.get_point_connections(mapping[star_icon.pos])
	
	for n in neighbors:
		var coords = unpack_vector(n)
		#print("unpacked coords: ", coords)
		coords = positive_to_original(coords)
		#print("Coords: ", coords)
		var icon = find_icon_for_pos(coords)	
		res.append(icon)

	return res

func get_route(src_icon, tg_icon):
	var src = null
	if not "pos" in src_icon: 
		src = mapping[Vector3(0,0,0)]
	else: 
		src = mapping[src_icon.pos]
	
	var tg = null
	if not "pos" in tg_icon: 
		tg = mapping[Vector3(0,0,0)]
	else: 
		tg = mapping[tg_icon.pos]
	
	#print("Route: " , route(src, tg))
	return route(src, tg)
	
func get_route_icons(src_icon, tg_icon):
	var r = get_route(src_icon, tg_icon)
	
	if r == null:
		return []
	
	var icons = []
#	for s in r:
#		var coords = unpack_vector(s)
#		#print("unpacked coords: ", coords)
#		coords = positive_to_original(coords)
#		#print("Coords: ", coords)
#		var icon = find_icon_for_pos(coords)	
#		#icons.append(icon)
	
	# arrange in pairs (for easier drawing later)
	for index in range(r.size()-1):
		var coords = unpack_vector(r[index])
		#print("unpacked coords: ", coords)
		coords = positive_to_original(coords)
		#print("Coords: ", coords)
		var icon = find_icon_for_pos(coords)
		coords = unpack_vector(r[index+1])
		coords = positive_to_original(coords)
		var icon2 = find_icon_for_pos(coords)
		icons.append([icon, icon2])
	
	#print(icons)
	return icons

func get_route_distance_height(src_icon, tg_icon):
	var dist = 0
	var data = []
	
	var r = get_route(src_icon, tg_icon)
	
	if r == null or r.empty():
		return []
	
	for i in range(r.size()-1):
		var p = r[i]
		var coords = unpack_vector(p)
#		#print("unpacked coords: ", coords)
		coords = positive_to_original(coords)
		#print("Coords: ", coords)
		
#		we'll need icons for names
#		var icon = find_icon_for_pos(coords)
		
		if i > 0:
			var prev = unpack_vector(r[i-1])
			prev = positive_to_original(prev)
			
			dist = dist + (coords-prev).length()
			#print("Appending data for i: ", i)
			data.append([dist, coords[2]]) # these are all fake integers, i.e. real value times 10
		else:
			dist = 0
			data.append([dist, coords[2]])

	var p = r[r.size()-1]
	var coords = unpack_vector(p)
	#print("unpacked coords: ", coords)
	coords = positive_to_original(coords)
	#print("Final coords: ", coords)
	var prev = unpack_vector(r[r.size()-2])
	prev = positive_to_original(prev)
	dist = dist + (coords-prev).length()
	data.append([dist, coords[2]])

	print("Route distances and heights: ", data)	
	return data


func pretty_print_stars(stars):
	for s in stars:
		var coords = float_to_int(s[1])
		var icon = find_icon_for_pos(coords)
		print(s[0], " @ ", s[1], " : ", icon.get_name())

func update_map(marker):
	# update marker position
	var system = get_tree().get_nodes_in_group("main")[0].curr_system

	if $"Control/Layer".has_node(system):
		marker.get_parent().remove_child(marker)
		$"Control/Layer".get_node(system).add_child(marker)
		$"Control".src = $"Control/Layer".get_node(system)
	if $"Control/LayerZ+".has_node(system):
		marker.get_parent().remove_child(marker)
		$"Control/LayerZ+".get_node(system).add_child(marker)
		$"Control".src = $"Control/LayerZ+".get_node(system)
	if $"Control/LayerZ-".has_node(system):
		marker.get_parent().remove_child(marker)
		$"Control/LayerZ-".get_node(system).add_child(marker)
		$"Control".src = $"Control/LayerZ-".get_node(system)

	if system == "tauceti":
		marker.get_parent().remove_child(marker)
		$"Control/Tau Ceti".add_child(marker)
		$"Control".src = $"Control/Tau Ceti"
	if system == "barnards":
		marker.get_parent().remove_child(marker)
		$"Control/Barnard's Star".add_child(marker)
		$"Control".src = $"Control/Barnard's Star"

	# clear any previous tint
	for l in get_node("Control").get_children():
		if l.get_name() == "ruler": # skip the ruler
			continue
			
		for c in l.get_children():
			c.get_node("Label").set_self_modulate(Color(1,1,1))
	
	# cyan is now used to indicate Z levels (see star map icon.gd)
	# cyan is also one of the 4 original Stellar Frontier fleet colors (cyan, red, green and yellow)
	# this is why the marker icon (handled above) is cyan - the player belongs to the cyan fleet
	# show target on map (tint hot purple to pop out)
	var lookup = {"Barnards":"Barnard's Star", "Trappist": "Trappist-1"}	
	
	if game.player.w_hole.target_system:
		print("Target system: ", game.player.w_hole.target_system)
		
		var coords = unpack_vector(game.player.w_hole.target_system)
		#print("unpacked coords: ", coords)
		coords = positive_to_original(coords)
		#print("Coords: ", coords)
		var icon = find_icon_for_pos(coords)
		if icon != null:
			print("Icon: ", icon.get_name(), " @ ", coords)
		$"Control".w_hole_tg = icon
		$"Control".tg = icon
		icon.get_node("Label").set_self_modulate(Color(1,0,1)) #hot pink purple
		# reveal Z line and planet icon for target
		if icon.has_node("Line2D"):
			icon.get_node("Line2D").show()
		icon.get_node("StarTexture").show()
		
		# paranoia
		if $"Control".src == $"Control".tg:
			print("Something went wrong, same src and tg!!!")
		
	else:
		if system == "Sol":
			$"Control/proxima/Label".set_self_modulate(Color(1,0,1))
		if system == "Proxima":
			$"Control/alphacen/Label".set_self_modulate(Color(1,0,1))
		if system == "Luyten 726-8":
			$"Control/Tau Ceti/Label".set_self_modulate(Color(1,0,1))
	
	# center on star (needs target to be set because it resets the distance label)
	offset = -($"Control".src.rect_position+$"Control".src.get_node("StarTexture").rect_position)
	move_map_to_offset(offset)
	
	# show distance involved along the line
	var tg_pos = get_node("Control").tg.rect_position
	if get_node("Control").tg.get_node("StarTexture").visible:
		tg_pos += get_node("Control").tg.get_node("StarTexture").rect_position
	
	get_node("Control/ruler").pts = [get_node("Control").src.rect_position, tg_pos]
	get_node("Control/ruler/Label").set("custom_colors/font_color", Color(1,0,1))
	get_node("Control/ruler/Line2D").default_color = Color(1,0,1)
	get_node("Control/ruler").set_ruler()

	var dist = get_star_distance($"Control".src, $"Control".tg)
	get_node("Control/ruler/Label").set_text("%.2f ly" % (dist))
	# update displayed starmap info
	display_star_map_info($"Control".tg)
	# force redraw side panel
	get_node("../../Control2/Panel_rightHUD/Control/RouteHeightPanel").show()
	get_node("../../Control2/Panel_rightHUD/Control/RouteHeightPanel").update()

func display_star_map_info(star_icon):
	var text = ""
	# actual text begins here
	text = text + star_icon.get_name() + "\n" + "\n"
	if not "star_type" in star_icon:
		text = text + "Star type/color: yellow \n"
	else:	 
		# basics
		text = text + "Star type/color: " + str(star_icon.star_type) + "\n"

	var fmt_multiple = "no" if not star_icon.multiple else str(star_icon.multiple)
	text = text + "Multiple system: " + fmt_multiple + "\n"
	var fmt_planets = "yes" if star_icon.planets else "no"
	text = text + "Planets: " + fmt_planets + "\n"
	var fmt_coord_x = "%.2f" % star_icon.x
	var fmt_coord_y = "%.2f" % star_icon.y 
	var fmt_coord_z = "%.2f" % star_icon.depth
	text = text + "X: " + str(fmt_coord_x) + " Y: " + str(fmt_coord_y) + " Z: " + str(fmt_coord_z) + "\n"
	
	text = text + str(pos_to_sector(star_icon.pos, false)) + "\n"
	
	# do nothing more if we're not in mapping
	if (star_icon.pos in mapping):
		pass
	else:
		# need to go up the tree and back down :/
		var rtl = $"../../Control2/Panel_rightHUD/PanelInfo/StarSystemInfo/RichTextLabel"
		rtl.set_text(text)
		
		print(star_icon.pos in mapping)
		print("Not in mapping! ", star_icon.pos)
		return
		
		
	# wormhole connections
	#var n = get_neighbors(star_icon.pos)
	# this one uses preconverted values unlike the function above
	var neighbors = map_astar.get_point_connections(mapping[star_icon.pos])
	
	var neighbors_text = ""
	for n in neighbors:
		var coords = unpack_vector(n)
		#print("unpacked coords: ", coords)
		coords = positive_to_original(coords)
		#print("Coords: ", coords)
		var icon = find_icon_for_pos(coords)
		
		neighbors_text += str(icon.get_name()) + ", " #str(n) would display the internal ID
	text = text + "Wormholes to: " + neighbors_text
	
	# need to go up the tree and back down :/
	var rtl = $"../../Control2/Panel_rightHUD/PanelInfo/StarSystemInfo/RichTextLabel"
	rtl.set_text(text)

# --------------------------------------------------
func display_captain_log():
	#$"PopupPanel/VBoxContainer/ButtonLog/PanelLog/RichTextLabel".set_text(str(game.captain_log))
	
	# same trick as in update_cargo_listing()
	var listing = str(game.captain_log).lstrip("[").rstrip("]").replace("], ", "\n").replace("[", "")	
	$"PopupPanel/VBoxContainer/ButtonLog/PanelLog/RichTextLabel".set_text(listing)

func _on_ButtonLog_pressed():
	if !$"PopupPanel/VBoxContainer/ButtonLog/PanelLog".is_visible():
		display_captain_log()
		$"PopupPanel/VBoxContainer/ButtonLog/PanelLog".show()
	else:
		$"PopupPanel/VBoxContainer/ButtonLog/PanelLog".hide()
	
# NOTE: offset is in px
func move_map_to_offset(offset):
	$Control.set_position(center+offset)
	$"Grid/VisControl".update() # redraw map lines if any
	
	var sector = str(pos_to_sector(Vector3(-offset.x/50, -offset.y/50, 0)))
	
	$Legend/Label.set_text("1 ly = 50 px" + "\n" + "Map pos: " + str(-offset) + " Sector: " + sector)
	if offset != Vector2(0,0):
		$Grid.origin = false
	else:
		$Grid.origin = true
	$Grid.update_grid()
	# recalculate starmap icons sfx
	for l in $"Control".get_children():
		for c in l.get_children():
			# because some star icons are hardcoded
			if c.has_method("calculate_label_and_sfx"):
				c.calculate_label_and_sfx(offset)
			


# ----------------------------------------------------	
func _on_ButtonConfirm_pressed():
	game.player.w_hole.jump()
	$"PopupPanel/VBoxContainer/ButtonLog/PanelLog".hide()
	get_node("../../Control2/Panel_rightHUD/Control/RouteHeightPanel").hide()

func _on_ButtonAbort_pressed():
	game.player.HUD.hide_starmap()
	$"PopupPanel/VBoxContainer/ButtonLog/PanelLog".hide()
	game.player.w_hole.entered = false
	game.player.w_hole = null
	get_node("../../Control2/Panel_rightHUD/Control/RouteHeightPanel").hide()
	
func _on_ButtonL_pressed():
	offset += Vector2(LY_TO_PX,0)
	move_map_to_offset(offset)

func _on_ButtonR_pressed():
	offset += Vector2(-LY_TO_PX,0)
	move_map_to_offset(offset)

func _on_ButtonUp_pressed():
	offset += Vector2(0, LY_TO_PX)
	move_map_to_offset(offset)

func _on_ButtonDown_pressed():
	offset += Vector2(0, -LY_TO_PX)
	move_map_to_offset(offset)


func _on_LineEdit_text_entered(new_text):
	# search for the star
	var found = null
	#for c in $Control.get_children():
	for l in $"Control".get_children():
		for c in l.get_children():
			if c.has_node("Label") and c.get_node("Label").get_text().find(new_text) != -1:
				found = c
				print("Found the star: ", new_text, "!")
				break
	
	# center map on found star
	# TODO: center on midpoint between star and shadow ONCE we're assured all stars fit in screen
	# i.e. layers are implemented
	if found:
		offset = -(found.rect_position) #+found.get_node("StarTexture").rect_position)
		move_map_to_offset(offset)
