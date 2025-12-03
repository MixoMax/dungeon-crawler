extends CharacterBody2D

const SPEED = 200.0
const TILE_DOOR = 3


func _physics_process(_delta):
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction:
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)
	
	# Change animation Frame from child node Sprite2D, according to movement direction
	if direction.x > 0:
		$Sprite2D.frame = 2  # Right
	elif direction.x < 0:
		$Sprite2D.frame = 3
	elif direction.y < 0:
		$Sprite2D.frame = 1
	elif direction.y > 0:
		$Sprite2D.frame = 0  # Downwds

	move_and_slide()

	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider is TileMapLayer:
			var hit_pos = collision.get_position() - collision.get_normal()
			var local_pos = collider.to_local(hit_pos)
			var cell_pos = collider.local_to_map(local_pos)
			
			if collider.get_cell_source_id(cell_pos) == TILE_DOOR:
				if get_parent().has_method("try_open_door"):
					get_parent().try_open_door(cell_pos)
