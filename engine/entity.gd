extends KinematicBody2D

class_name Entity

# ATTRIBUTES
export(String, "ENEMY", "PLAYER", "TRAP") var TYPE = "ENEMY"
export(float, 0.5, 20, 0.5) var MAX_HEALTH = 1
export(int) var SPEED = 70
export(float, 0, 20, 0.5) var DAMAGE = 0.5

# MOVEMENT
var movedir = Vector2(0,0)
var knockdir = Vector2(0,0)
var spritedir = "Down"
var last_movedir = Vector2(0,1)

# COMBAT
var health = MAX_HEALTH setget set_health
var hitstun = 0
signal health_changed
signal hitstun_end

var state = "default"
var home_position = Vector2(0,0)

onready var anim = $AnimationPlayer
onready var sprite = $Sprite
var hitbox : Area2D
var center : Area2D
var camera
var tween
var grass_movement

var pos = Vector2(0,0) setget position_changed
var animation = "idleDown" setget animation_changed

func _ready():
	set_process(false)
	add_to_group("entity")
	if !sprite.material:
		sprite.material = ShaderMaterial.new()
		sprite.material.set_shader(preload("res://engine/entity.shader"))
	health = MAX_HEALTH
	home_position = position
	create_hitbox()
	create_center()
	create_tween()
	grass_movement = preload("res://effects/grass_movement.tscn").instance()
	add_child(grass_movement)
	#get_parent().connect("player_entered", self, "player_entered")
	set_process(true)

func _process(delta):
	grass_movement.hide()
	for body in center.get_overlapping_bodies():
		if body.name == "tall_grass":
			grass_movement.show()
			grass_movement.frame = sprite.frame % 2
			#grass_movement.global_position = sprite.global_position.snapped(Vector2(1,1))

func create_hitbox():
	var new_hitbox = Area2D.new()
	add_child(new_hitbox)
	new_hitbox.name = "Hitbox"
	
	var new_collision = CollisionShape2D.new()
	new_hitbox.add_child(new_collision)
	
	var new_shape = CapsuleShape2D.new()
	new_collision.shape = new_shape
	new_shape.radius = $CollisionShape2D.shape.radius + 1
	new_shape.height = $CollisionShape2D.shape.height + 1
	
	hitbox = new_hitbox

func create_center():
	var new_center = Area2D.new()
	add_child(new_center)
	new_center.name = "Center"
	
	var new_collision = CollisionShape2D.new()
	new_center.add_child(new_collision)
	
	var new_shape = RectangleShape2D.new()
	new_collision.shape = new_shape
	new_shape.extents = Vector2(1,1)
	
	# tall_grass
	new_center.set_collision_layer_bit(0,1)
	new_center.set_collision_mask_bit(0,1)
	new_center.set_collision_layer_bit(5,1)
	new_center.set_collision_mask_bit(5,1)
	
	new_center.position.y += 6
	
	center = new_center

func create_tween():
	var new_tween = Tween.new()
	add_child(new_tween)
	tween = new_tween

func loop_movement():
	var motion
	if hitstun == 0:
		motion = movedir.normalized() * SPEED
	else:
		motion = knockdir.normalized() * 125
	
	move_and_slide(motion)
	
	pos = position
	
	if movedir != Vector2.ZERO:
		last_movedir = movedir

func loop_spritedir():
	var old_spritedir = spritedir
	
	match movedir:
		Vector2.LEFT:
			spritedir = "Left"
		Vector2.RIGHT:
			spritedir = "Right"
		Vector2.UP:
			spritedir = "Up"
		Vector2.DOWN:
			spritedir = "Down"
	
	sprite.flip_h = (spritedir == "Left")

func loop_damage():
	if hitstun > 1:
		hitstun -= 1
		if sprite.material.get_shader_param("is_hurt") == false:
			set_hurt_texture(true)
			network.peer_call(self, "set_hurt_texture", [true])
	elif hitstun == 1:
		if sprite.material.get_shader_param("is_hurt") == true:
			set_hurt_texture(false)
			network.peer_call(self, "set_hurt_texture", [false])
		emit_signal("hitstun_end")
		hitstun -= 1
	
	for area in hitbox.get_overlapping_areas():
		if area.name != "Hitbox":
			continue
		var body = area.get_parent()
		if !body.get_groups().has("entity") && !body.get_groups().has("item"):
			continue
		if hitstun == 0 && body.get("DAMAGE") > 0 && body.get("TYPE") != TYPE:
			update_health(-body.DAMAGE)
			hitstun = 10
			knockdir = global_position - body.global_position
			if body.has_method("hit"):
				body.hit()

func update_health(amount):
	health = max(min(health + amount, MAX_HEALTH), 0)
	emit_signal("health_changed")

remote func set_hurt_texture(h):
	sprite.material.set_shader_param("is_hurt", h)

func anim_switch(a):
	var newanim: String = str(a, spritedir)
	if ["Left","Right"].has(spritedir):
		newanim = str(a, "Side")
	if anim.current_animation != newanim:
		anim.play(newanim)
	animation = newanim

sync func use_item(item, input):
	var newitem = load(item).instance()
	var itemgroup = str(item, name)
	newitem.add_to_group(itemgroup)
	newitem.add_to_group(name)
	add_child(newitem)
	
	newitem.set_network_master(get_network_master())
	
	if get_tree().get_nodes_in_group(itemgroup).size() > newitem.MAX_AMOUNT:
		newitem.delete()
		return
	
	newitem.input = input
	newitem.start()

func position_changed(value):
	pos = value
	tween.interpolate_property(self, "position", position, pos, network.tick_time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	tween.start()

func animation_changed(value):
	animation = value
	if anim.current_animation != value:
		anim.play(value)

func set_health(value):
	health = value
