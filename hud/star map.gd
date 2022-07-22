# map emulates the look of http://www.projectrho.com/public_html/rocket/images/spacemaps/RECONSmap.jpg

tool
extends Control


# Declare member variables here. Examples:

var icon = preload("res://hud/star map icon.tscn")

# data
var data = []
# map
var map_graph = []
var map_astar = null

func save_graph_data(x,y,z, nam):
	map_graph.append([x,y,z, nam])

# Called when the node enters the scene tree for the first time.
func _ready():
	data = load_data()
	for line in data:
		# name, x, y, z, color
		#print(line)
		if line[0] != "Sol" and line[0] != "Tau Ceti":
			var ic = icon.instance()
			ic.named = str(line[0])
			if line[1] != " -":
				# strip units
				ic.x = strip_units(str(line[1]))
				#ic.x = float(line[1])
				ic.y = strip_units(str(line[2]))
				ic.depth = strip_units(str(line[3]))
				# does the star have planets?
				ic.planets = false
				if "yes" in line[5]:
					ic.planets = true
				save_graph_data(ic.x, ic.y, ic.depth, ic.named)
			
			# test ra-dec conversion
			if line.size() > 7 and line[1] == " -":
				var ra = line[7]
				var de = line[8] 
				if ra != "" and de != "" and line[9] != "":
					var ra_deg = 0
					var dec = 0
					if "h" in ra and not "m" in ra:
						# if no minutes specified, we assume decimal hours
						# 15 degrees in an hour (360/24) 
						ra_deg = float(15*float(ra.rstrip("h")))
						# for now, assume degrees are given in decimal degrees
						dec = float(line[7])
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
					
					var data = galactic_from_ra_dec(ra_deg, dec, float(line[9]))
					# assign calculated values - no need to strip units as it's always
					ic.x = data[0]
					ic.y = data[1]
					ic.depth = data[2]
					save_graph_data(ic.x, ic.y, ic.depth, ic.named)
			get_node("Control").add_child(ic)
	
	# create a graph of stars we can route on
	create_map_graph()
	
func strip_units(entry):
	var num = 0.0
	if "ly" in entry:
		num = float(entry.rstrip("ly"))
	elif "pc" in entry:
		num = float(entry.rstrip("pc"))
	return num

# based on Winchell Chung's Star3D spreadsheet and 
# http://starmap.whitten.org/files/src/gal_pl.txt
# input in degrees by default!!!
# output is in whatever unit dist used (light years in my case)
func galactic_from_ra_dec(ra, dec, dist):
	# Find Equatorial cartesian coordinates
	ra = deg2rad(ra)
	dec = deg2rad(dec)
	# dec and ra in radians from here on
	var rvect = dist * cos(dec);

	var equat_x = rvect * cos(ra);
	var equat_y = rvect * sin(ra);
	var equat_z = dist * sin(dec);
	
	# Find Galactic cartesian coordinates
	var xg = -(.055 * equat_x) - (.8734 * equat_y) - (.4839 * equat_z);
	var yg =  (.494 * equat_x) - (.4449 * equat_y) + (.747 * equat_z);
	var zg = -(.8677 * equat_x) - (.1979 * equat_y) + (.4560 * equat_z);
	
	var gal = Vector3(xg, yg, zg)
	print("Galactic coords: ", gal)
	return gal

func load_data():
	var file = File.new()
	var opened = file.open("res://hud/starmap.csv", file.READ)
	if opened == OK:
		while !file.eof_reached():
			var csv = file.get_csv_line()
			if csv != null:
				# skip header
				if csv[0] == "name":
					continue
				# skip empty lines
				if csv.size() > 1:
					data.append(csv)
					#print(str(csv))
	
		file.close()
		return data


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func update_marker(marker):
	# update marker position
	var system = get_tree().get_nodes_in_group("main")[0].curr_system

	if $"Control".has_node(system):
		marker.get_parent().remove_child(marker)
		$"Control".get_node(system).add_child(marker)

	if system == "tauceti":
		marker.get_parent().remove_child(marker)
		$"Control/tau ceti".add_child(marker)
	if system == "barnards":
		marker.get_parent().remove_child(marker)
		$"Control/Barnard's Star".add_child(marker)

	# clear any previous tint
	for c in get_node("Control").get_children():
		c.get_node("Label").set_self_modulate(Color(1,1,1))
	
	# show target on map (tint cyan)	
	#var lookup = {"luyten726-8": "Luyten 726-8", "barnards":"Barnard's Star", "wolf359":"Wolf 359"}	
	var lookup = {"Barnards":"Barnard's Star"}	
	
	if game.player.w_hole.target_system:
		print("Target system: ", game.player.w_hole.target_system)
		if game.player.w_hole.target_system in lookup:
			get_node("Control").get_node(lookup[game.player.w_hole.target_system]).get_node("Label").set_self_modulate(Color(0,1,1))
		else:
			get_node("Control").get_node(game.player.w_hole.target_system).get_node("Label").set_self_modulate(Color(0,1,1))
	else:
		if system == "Sol":
			$"Control/proxima/Label".set_self_modulate(Color(0,1,1))
		if system == "Proxima":
			$"Control/alphacen/Label".set_self_modulate(Color(0,1,1))
		if system == "Luyten 726-8":
			$"Control/tau ceti/Label".set_self_modulate(Color(0,1,1))
	
	# TODO: show distances, too

func create_map_graph():
	map_astar = AStar.new()
	# hardcoded stars
	map_astar.add_point(0, Vector3(0,0,0)) # Sol
	map_astar.add_point(1, Vector3(-3.4, 0.4, -11.4)) # Tau Ceti
	
	# graph is made out of nodes
	for i in map_graph.size():
		var n = map_graph[i]
		map_astar.add_point(i+2, Vector3(n[0], n[1], n[2]))
	
	# connect stars
	map_astar.connect_points(0,1) # Sol to Tau Ceti
	map_astar.connect_points(0,2) # Sol to Barnard's
	map_astar.connect_points(0,3) # Sol to Wolf359
	map_astar.connect_points(0,4) # Sol to Luyten 726-8/UV Ceti
	
#	# check distances to Gliese 1002
#	for i in range(4):
#		var dist = map_astar.get_point_position(i).distance_to(map_astar.get_point_position(7))
#		print(i, ": ", dist)
	
	map_astar.connect_points(1,7) # Tau Ceti to Gliese 1002 (6.8ly according to the above)
	map_astar.connect_points(5,7) # Gliese 1005 to Gliese 1002
	map_astar.connect_points(7,8) # Gliese 1002 to Gliese 1286
	map_astar.connect_points(8,9) # Gliese 1286 to Gliese 867 (FK Aquarii)
	map_astar.connect_points(10,9) # Gliese 1265 to Gliese 867
	map_astar.connect_points(11,10) # NN 4281 to Gliese 1265
	map_astar.connect_points(11,12) # NN 4281 to TRAPPIST-1
	
	# debug
	for p in map_astar.get_points():
		print(p, ": ", map_astar.get_point_position(p))
		
	# check connectedness
	print("To TRAPPIST: ", map_astar.get_id_path(0,12))
		
	return map_astar

# --------------------------------------------------
func _on_ButtonConfirm_pressed():
	game.player.w_hole.jump()
	$"PopupPanel/VBoxContainer/ButtonLog/PanelLog".hide()

func _on_ButtonAbort_pressed():
	game.player.HUD.hide_starmap()
	$"PopupPanel/VBoxContainer/ButtonLog/PanelLog".hide()

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
	
	
