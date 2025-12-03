extends Node

@export var tile_map_layer: TileMapLayer
@export var player_scene: PackedScene

const TILE_WALL = 0
const TILE_FLOOR = 1
const TILE_CHEST = 2
const TILE_DOOR = 3

const ROOM_MAX_SIZE = 12
const ROOM_MIN_SIZE = 6

# Stores all room rectangles (visible + virtual) to prevent overlaps
var rooms: Array[Rect2i] = []

# Maps a Door Position (Vector2i) -> The Virtual Room Rect (Rect2i) waiting behind it
var pending_rooms = {} 

func _ready():
	randomize()
	tile_map_layer.clear()
	rooms.clear()
	pending_rooms.clear()
	
	# Create the starting room
	var start_room = Rect2i(-5, -5, 10, 10)
	rooms.append(start_room)
	realize_room(start_room)
	
	# Spawn Player
	var start_pos = start_room.get_center()
	if player_scene:
		var player = player_scene.instantiate()
		player.position = tile_map_layer.map_to_local(start_pos)
		add_child(player)

func try_open_door(door_pos: Vector2i):
	# Check if this is a known door with a virtual room behind it
	if not pending_rooms.has(door_pos):
		return

	var new_room_rect = pending_rooms[door_pos]
	
	# 1. Build the new room visuals (Walls/Floors)
	realize_room(new_room_rect)
	
	# 2. Open the Door itself (The wall of the OLD room)
	tile_map_layer.set_cell(door_pos, TILE_FLOOR, Vector2i(0, 0))
	
	# 3. Punch a hole in the NEW room's wall
	# Since we have double walls, the new room has a wall directly facing the door.
	# We check the 4 neighbors of the door; whichever is inside the new room is the entrance.
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for n in neighbors:
		var neighbor_pos = door_pos + n
		if new_room_rect.has_point(neighbor_pos):
			# This neighbor is inside the new room bounds, so it's the blocking wall
			tile_map_layer.set_cell(neighbor_pos, TILE_FLOOR, Vector2i(0, 0))
	
	# 4. Remove from pending since it's now real
	pending_rooms.erase(door_pos)

# --- VISUAL GENERATION ---

func realize_room(room: Rect2i):
	# 1. Fill Floor (Inner area)
	for x in range(room.position.x + 1, room.end.x - 1):
		for y in range(room.position.y + 1, room.end.y - 1):
			tile_map_layer.set_cell(Vector2i(x, y), TILE_FLOOR, Vector2i(0, 0))
			
	# 2. Process Walls (Perimeter) to find NEW doors
	# We explicitly pass the "Outward" direction for each wall
	
	# Top Wall (Normal: UP)
	for x in range(room.position.x + 1, room.end.x - 1):
		process_wall_tile(Vector2i(x, room.position.y), Vector2i.UP)
		
	# Bottom Wall (Normal: DOWN)
	for x in range(room.position.x + 1, room.end.x - 1):
		process_wall_tile(Vector2i(x, room.end.y - 1), Vector2i.DOWN)
		
	# Left Wall (Normal: LEFT)
	for y in range(room.position.y + 1, room.end.y - 1):
		process_wall_tile(Vector2i(room.position.x, y), Vector2i.LEFT)
		
	# Right Wall (Normal: RIGHT)
	for y in range(room.position.y + 1, room.end.y - 1):
		process_wall_tile(Vector2i(room.end.x - 1, y), Vector2i.RIGHT)

	# 3. Corners (Always walls)
	fill_corners(room)

	# 4. Random Chest
	if randf() < 0.5:
		var chest_pos = Vector2i(
			randi_range(room.position.x + 2, room.end.x - 3),
			randi_range(room.position.y + 2, room.end.y - 3)
		)
		tile_map_layer.set_cell(chest_pos, TILE_CHEST, Vector2i(0, 0))

func fill_corners(room: Rect2i):
	var corners = [
		Vector2i(room.position.x, room.position.y),
		Vector2i(room.end.x - 1, room.position.y),
		Vector2i(room.position.x, room.end.y - 1),
		Vector2i(room.end.x - 1, room.end.y - 1)
	]
	for c in corners:
		# Don't overwrite floors (connections)
		if tile_map_layer.get_cell_source_id(c) != TILE_FLOOR:
			tile_map_layer.set_cell(c, TILE_WALL, Vector2i(0, 0))

func process_wall_tile(pos: Vector2i, direction: Vector2i):
	if tile_map_layer.get_cell_source_id(pos) == TILE_FLOOR: return
	if tile_map_layer.get_cell_source_id(pos) == TILE_DOOR: return

	# 15% Chance to be a door, IF we can reserve a valid room behind it
	if randf() < 0.15:
		var reserved_room = reserve_virtual_room(pos, direction)
		if reserved_room.has_area():
			tile_map_layer.set_cell(pos, TILE_DOOR, Vector2i(0, 0))
			pending_rooms[pos] = reserved_room
		else:
			tile_map_layer.set_cell(pos, TILE_WALL, Vector2i(0, 0))
	else:
		tile_map_layer.set_cell(pos, TILE_WALL, Vector2i(0, 0))

# --- LOGIC & CALCULATION ---

func reserve_virtual_room(door_pos: Vector2i, direction: Vector2i) -> Rect2i:
	var room_rect = find_best_fit_room(door_pos, direction)
	if room_rect.has_area():
		# Block this space immediately so other doors don't use it
		rooms.append(room_rect)
		return room_rect
	return Rect2i()

func find_best_fit_room(door_pos: Vector2i, direction: Vector2i) -> Rect2i:
	var forward = direction
	var right = Vector2i(direction.y, -direction.x)
	
	# Heuristic: Try largest depth first, shrink if blocked
	var max_scan_depth = randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
	
	for d in range(max_scan_depth, ROOM_MIN_SIZE - 1, -1):
		# 1. Check Spine (straight line)
		var spine_valid = true
		for k in range(1, d):
			if is_tile_occupied(door_pos + (forward * k)):
				spine_valid = false; break
		if not spine_valid: continue 

		# 2. Expand Sideways
		var max_left = 0
		var max_right = 0
		var desired_width = randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var half_width = int(desired_width / 2)
		
		# Scan Right
		for r in range(1, half_width + 1):
			if check_rect_collision(door_pos, forward, right, d, r, max_left): break
			max_right = r
		
		# Scan Left
		for l in range(1, half_width + 2):
			if check_rect_collision(door_pos, forward, right, d, max_right, -l): break
			max_left = -l
			
		var total_width = max_right - max_left + 1
		
		if total_width >= ROOM_MIN_SIZE:
			# Convert Local (Forward/Right) -> Global (X/Y) Rect
			var start_local = (forward * 1) + (right * max_left)
			var size_local = (forward * (d - 1)) + (right * (total_width - 1))
			var p1 = door_pos + start_local
			var p2 = door_pos + start_local + size_local
			
			var min_x = min(p1.x, p2.x); var max_x = max(p1.x, p2.x)
			var min_y = min(p1.y, p2.y); var max_y = max(p1.y, p2.y)
			
			return Rect2i(min_x, min_y, (max_x - min_x) + 1, (max_y - min_y) + 1)
			
	return Rect2i()

func check_rect_collision(origin, fwd, right, depth, right_offset, left_offset) -> bool:
	var p1 = origin + (fwd * 1) + (right * left_offset)
	var p2 = origin + (fwd * (depth - 1)) + (right * right_offset)
	
	var min_x = min(p1.x, p2.x); var min_y = min(p1.y, p2.y)
	var test_rect = Rect2i(min_x, min_y, abs(p1.x - p2.x) + 1, abs(p1.y - p2.y) + 1)
	
	for r in rooms:
		# Check if new room intersects existing FLOORs (allow touching walls)
		if test_rect.intersects(r.grow(-1)): 
			return true
	return false

func is_tile_occupied(pos: Vector2i) -> bool:
	for r in rooms:
		if r.has_point(pos): return true
	return false
