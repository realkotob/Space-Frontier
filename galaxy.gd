extends Node

# Declare member variables here. Examples:
# data
var data = []
# map
var map_graph = []
var map_astar = null
# problem: we have coordinates (3 floats) and we need to have a unique identifier per star
# idenfifier must be an int because AStar uses integer ids
var mapping = {}

# https://stackoverflow.com/questions/65706804/bitwise-packing-unpacking-generalized-solution-for-arbitrary-values
# for some reason this (just like collapsing 3D to 1D index) only works for positive numbers
# https://stackoverflow.com/questions/6556961/use-of-the-bitwise-operators-to-pack-multiple-values-in-one-int/6557022#6557022
# no component can be bigger then 999 that means we need 10 bits of storage per component (allows numbers up to 1014).
func pack_vector(vec3):
	# packed = v3 << (size1 + size2) | v2 << size1 | v1;
	return (int(vec3.z) << (10 + 10) | int(vec3.y) << 10 | int(vec3.x))
	
func unpack_vector(id):
	#var sample1 = int(pow(2,10+1)-1) #511 (8+1) #1023 (9+1) #2047 (10+1); #pow(2, 10+1)-1;
	#var sample2 = int(pow(2,10+1)-1) #pow(2,10+1)-1;
	#print(sample1)
	
	var mask = ((1 << 10) - 1) # mask hides all the bits of the left except the 10 rightmost
	var v1 = (id >> 0) & mask
	var v2 = (id >> 10) & mask
	var v3 = id >> (10 + 10) & mask
	return Vector3(v1, v2, v3)

func float_to_int(vec3):
	#print("original: ", vec3)
	# TODO: Godot4 - use Vector3i here
	# integer that represents a float with one decimal place (shave off the last to know the decimals)
	return Vector3(int(float("%.1f" % vec3.x)*10),int(float("%.1f" % vec3.y)*10), int(float("%.1f" % vec3.z)*10))

func pos_to_positive_pos(vec3):
	# assume the sector is 50 ly in each direction, extended to closest power of 2
	# a digit was added to represent a decimal place (see l.29 above)
	var sector_start = Vector3(-512,-512,-512)
	var pos = Vector3(vec3.x-sector_start.x, vec3.y-sector_start.y, vec3.z-sector_start.z)
	#print("original: ", vec3, " positive: ", pos)
	# test
	#positive_to_original(pos)
	return pos
	
func positive_to_original(vec3):
	var sector_start = Vector3(-512,-512,-512)
	var pos = Vector3(vec3.x+sector_start.x, vec3.y+sector_start.y, vec3.z+sector_start.z)
	#print("positive: ", vec3, " original: ", pos)
	return pos


func save_graph_data(x,y,z, nam):
	map_graph.append([x,y,z, nam])
	
	# skip any stars outside the sector
	if x < -50 or y < -50 or z < -50:
		return
	
	# as of Godot 3.5, AStar's key cannot be larger than 2^32-1 (hashes will overflow)
	
	var id = pack_vector(pos_to_positive_pos(float_to_int(Vector3(x,y,z))))
	#print("ID: ", id, "; unpacked: ", unpack_vector(id))
	#print("Nearest po2: ", nearest_po2(id)) # 2^30 for storing 3*2^10 max
	#print("AStar overflow: ", id > (pow(2,31)-1)) # 2^31-1
	
	mapping[float_to_int(Vector3(x,y,z))] = id
	
	# the global scope function returns an integer hash
	#mapping[Vector3(x,y,z)] = hash(Vector3(x,y,z))
	# https://godotengine.org/qa/43078/create-an-unique-id
	#mapping[Vector3(x,y,z)] = Vector3(x,y,z).get_instance_id()

	
func strip_units(entry):
	var num = 0.0
	if "ly" in entry:
		num = float(entry.rstrip("ly"))
	elif "pc" in entry:
		num = float(entry.rstrip("pc"))*3.26
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
	#print("Galactic coords: ", gal)
	return gal

# parsing it happens in star_map.gd because it's creating the icons as it's being parsed
func load_data():
	var file = File.new()
	var opened = file.open("res://known_systems.csv", file.READ)
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

func create_map_graph():
	map_astar = AStar.new()
	# hardcoded stars
	mapping[Vector3(0,0,0)] = pack_vector(pos_to_positive_pos(float_to_int(Vector3(0,0,0))))
	map_astar.add_point(mapping[Vector3(0,0,0)], Vector3(0,0,0)) # Sol
	
	# graph is made out of nodes
	for i in map_graph.size():
		var n = map_graph[i]
		
		# skip any stars outside the sector
		if n[0] < -50 or n[1] < -50 or n[2] < -50:
			continue
		
		# the reason for doing this is to be independent of any sort of a catalogue ordering...
		map_astar.add_point(mapping[float_to_int(Vector3(n[0], n[1], n[2]))], Vector3(n[0], n[1], n[2]))
		#map_astar.add_point(i+1, Vector3(n[0], n[1], n[2]))
	
	# debug
	print("AStar points:")
	for p in map_astar.get_points():
		print(p, ": ", map_astar.get_point_position(p))
	
	# connect stars
	var data = auto_connect_stars()
	return data # for debugging
	
func auto_connect_stars():
	# we're not using Kruskal as we don't have edges
	# Prim's algorithm: start with one vertex
	# 1. Find the edges that connect to other vertices. Find the edge with minimum weight and add it to the spanning tree.
	# Repeat step 1 until the spanning tree is obtained.
	# i.e. step 1 is: get closest stars[1]... since [0] is ourselves
	var V = map_astar.get_points().size()
	var in_mst = [] # unlike most Prim exmaples, we store positions here, not just bools
	# preallocate for speedup
	in_mst.resize(V)
	in_mst.fill(0)
	var edge_count = 0
	in_mst[0] = Vector3(0,0,0)
	
	var tree = [] # separate struct for other connections
	tree.resize(V)
	tree.fill(0)
	
	while edge_count < V-1:
		# Find closest star to each star
		var pos = in_mst[edge_count]
		var stars = get_closest_stars_to(pos)
		# some postprocessing to remove one of a pair of very close stars
		stars = closest_stars_postprocess(stars)
		# sometimes the closest star is already in mst
		for c in range(1,stars.size()-1):
			if !in_mst.has(float_to_int(stars[c][1])):
				#print("Star, ", stars[c], " not in mst...")
				edge_count += 1
				in_mst[edge_count] = float_to_int(stars[c][1])
			# add the next closest star to a separate listing
			if !tree.has(float_to_int(stars[c+1][1])) and !in_mst.has(float_to_int(stars[c+1][1])):
				#print("Star, ", stars[c+1][1], " to be added to tree")
				tree[edge_count] = float_to_int(stars[c+1][1])
				break # no need to keep looking through closest stars if we already found
			#else:
				
			
	#print(in_mst)
	# convert mst to connections
	for i in range(1,in_mst.size()-1):
		map_astar.connect_points(mapping[in_mst[i-1]], mapping[in_mst[i]])
	for i in range(1, tree.size()-1):
		if !typeof(tree[i]) == TYPE_VECTOR3:
			continue # paranoia skip
		map_astar.connect_points(mapping[in_mst[i-1]], mapping[tree[i]])

		#print("Connecting: ", in_mst[i-1], " and ", tree[i])

	# manually add Sol's connections (for now) since that's what the wormhole setup script expects...
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(28, -31, 1)]) # Sol to Proxima Centauri
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(50, 30,14)]) # Sol to Barnard's
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(-19, -39, 65)]) # Sol to Wolf359
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(-21, 2, -85)]) # Sol to Luyten 726-8/UV Ceti
	

	return [map_astar, in_mst, tree]

func manual_connect():
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(28, -31, 1)]) # Sol to Proxima Centauri
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(50, 30,14)]) # Sol to Barnard's
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(-19, -39, 65)]) # Sol to Wolf359
	map_astar.connect_points(mapping[Vector3(0,0,0)], mapping[Vector3(-21, 2, -85)]) # Sol to Luyten 726-8/UV Ceti
	
	map_astar.connect_points(mapping[Vector3(-34, 4, -114)], mapping[Vector3(-21, 2, -85)]) # Tau Ceti to Luyten 726-8
	map_astar.connect_points(mapping[Vector3(28,-31,1)], mapping[Vector3(29, -31, 1)]) # Proxima to Alpha Centauri

	map_astar.connect_points(mapping[Vector3(50, 30, 14)], mapping[Vector3(29, -31, 1)]) # both Centauri connect to Barnard's
	#map_astar.connect_points(mapping[Vector3(50, 30, 14)], mapping[Vector3(28, -31, 1)])
	
	map_astar.connect_points(mapping[Vector3(-94, 34, -75)], mapping[Vector3(-34, 4, -114)]) # Tau Ceti to Teegarden's
	map_astar.connect_points(mapping[Vector3(-21, 2, -85)], mapping[Vector3(-68, -19, -78)]) # UV Ceti to Epsilon Eridani

	map_astar.connect_points(mapping[Vector3(50, 30,14)], mapping[Vector3(93, 19, -17)]) # Barnard's to Ross 154
	map_astar.connect_points(mapping[Vector3(93, 19, -17)], mapping[Vector3(92,6,-90)]) # Ross 154 to AX Microscopii
	map_astar.connect_points(mapping[Vector3(-19, -39, 65)], mapping[Vector3(15, -43, 136)]) # Wolf 359 to FL Virginis 
#	map_astar.connect_points(mapping[Vector3(53, 8, 169)], mapping[Vector3(15, -43, 136)]) # Wolf 498 to FL Virginis 

	map_astar.connect_points(mapping[Vector3(-34, -3, 75)], mapping[Vector3(1, -56, 93)]) # Lalande 21185 to Ross 128
	map_astar.connect_points(mapping[Vector3(-34, -3, 75)], mapping[Vector3(-19, -39, 65)]) # Lalande 21185 to Wolf 359

	map_astar.connect_points(mapping[Vector3(-58, -62, -13)], mapping[Vector3(-92, -62, 26)]) # Sirius to Procyon
	map_astar.connect_points(mapping[Vector3(-92, -62, 26)], mapping[Vector3(-95, -29, 63)]) # Procyon to DX Cancri
	map_astar.connect_points(mapping[Vector3(-92, -62, 26)], mapping[Vector3(-103, -65, 22)]) # Procyon to Luyten's star

	map_astar.connect_points(mapping[Vector3(-34, 4, -114)],mapping[Vector3(-2, 58, -141)]) # Tau Ceti to Gliese 1002
#	map_astar.connect_points(mapping[Vector3(4, 39, -158)],mapping[Vector3(-2, 58, -141)]) # Gliese 1005 to Gliese 1002
#	map_astar.connect_points(mapping[Vector3(-2, 58, -141)],mapping[Vector3(14, 119,-202)]) # Gliese 1002 to Gliese 1286
#	map_astar.connect_points(mapping[Vector3(14, 119,-202)],mapping[Vector3(113, 95, -241)]) # Gliese 1286 to Gliese 867 (FK Aquarii)
#	map_astar.connect_points(mapping[Vector3(160, 130, -270)],mapping[Vector3(113, 95, -241)]) # Gliese 1265 to Gliese 867
#	map_astar.connect_points(mapping[Vector3(139, 155, -287)],mapping[Vector3(160, 130, -270)]) # NN 4281 to Gliese 1265
#	map_astar.connect_points(mapping[Vector3(139, 155, -287)],mapping[Vector3(78, 211, -339)]) # NN 4281 to TRAPPIST-1
	
		
	# check connectedness
#	print("To TRAPPIST: ", map_astar.get_id_path(mapping[Vector3(0,0,0)],mapping[Vector3(78, 211, -339)])) #12))
		


# this is why we don't nuke map_graph after creating the Astar graph...
func find_graph_id(nam):
	print("Looking up graph id for: ", nam)
	var id = -1
	for i in map_graph.size():
		var n = map_graph[i]
		if n[3] == nam:
			id = i #+1 # +1 because Sol is hardcoded at #0 (see l.200)
			break
	return id

func find_coords_for_name(nam):
	var id = find_graph_id(nam)
	var coords = Vector3(0,0,0)
	if id != -1:
		coords = Vector3(map_graph[id][0], map_graph[id][1], map_graph[id][2])
	print("For name, ", nam, " id ", id, " real float coords: ", coords)
	return coords
	

func get_star_distance_old(a,b):
	var start_name = a.get_node("Label").get_text().replace("*", "")
	var end_name = b.get_node("Label").get_text().replace("*", "")
	var id1 = find_graph_id(start_name)
	var id2 = find_graph_id(end_name)
	#print("ID # ", id1, " ID # ", id2, " pos: ", map_astar.get_point_position(id1), " & ", map_astar.get_point_position(id2))
	# see above - astar graph is created from map_graph so the id's match
	return map_astar.get_point_position(id1).distance_to(map_astar.get_point_position(id2))

func get_star_distance(a,b):
	var start = a.pos if "pos" in a else Vector3(0,0,0)
	var end = b.pos if "pos" in b else Vector3(0,0,0)
	var id1 = mapping.get(start)
	var id2 = mapping.get(end)
	print("id1:", id1, " id2: ", id2)
	return map_astar.get_point_position(id1).distance_to(map_astar.get_point_position(id2))

# converts float to int
func get_neighbors(coords):
	var neighbors = map_astar.get_point_connections(mapping[float_to_int(coords)])
	print("Neighbors for id: ", mapping[float_to_int(coords)], " ", neighbors)
	return neighbors

# sort
class MyCustomSorter:
	static func sort_stars(a, b):
		if a[0] < b[0]:
			return true
		return false

func get_closest_stars_to(pos):
	var src = map_astar.get_point_position(mapping[pos])
	
	#print("Getting closest stars to ", src)
	# sort by dist
	var dists = []
	var stars = []

	for p in map_astar.get_points():
		var dist = map_astar.get_point_position(p).distance_to(src)
		dists.append(dist)
		stars.append([dist, map_astar.get_point_position(p)])

	#dists.sort()
	#print("Dists sorted: " + str(dists))

	# custom sort
	stars.sort_custom(MyCustomSorter, "sort_stars")

	#print(stars)
	
	return stars

func closest_stars_postprocess(stars):
	var to_rem = []
	for i in range(1, stars.size()-1):
		var s = stars[i]
		var s_next = stars[i+1]
		#print("Comparing ", (s[1]-s_next[1]).length())
		if (s[1]-s_next[1]).length() < 0.15:
		#if abs(s[0]-s_next[0]) < 0.1:
			print("Detected two close stars in the list! ", s[1], s_next[1])
			to_rem.append(i+1)
	
	for r in to_rem:
		stars.remove(r)
	
	return stars

# wants internal ids
func route(src, tg):
	if tg in map_astar.get_point_connections(src):
		return
		
	if map_astar.get_point_connections(tg).size() < 1:
		return
		
	return map_astar.get_id_path(src, tg)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
