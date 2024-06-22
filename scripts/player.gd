extends CharacterBody3D



@export_category("Movement")
@export 
var walk_speed: float;
@export
var walk_acceleration: float;
@export
var walk_friction: float;
@export
var air_speed: float;
@export
var air_acceleration: float;
@export
var slide_speed: float;
@export
var slide_acceleration: float;
@export
var slide_friction: float;
@export
var slide_min_speed: float;
@export
var jump_impulse: float;
@export
var jump_buffer_time: float;



@export_category("Camera")
@export
var view_sensitive: float;
@export
var view_limit: float;
@export
var headbob_frequency: float;
@export
var headbob_amplitude: float;
@export
var fov: float;
@export
var fov_factor: float;
@export
var fov_decay: float;



@export_category("Slide")
@export
var slide_height: float;
@export
var slide_head_tilt: float;



@onready 
var head: Node3D = $Head;
@onready
var camera: Camera3D = $Head/Camera;
@onready
var collision_shape: CollisionShape3D = $CollisionShape;
@onready
var capsule_shape := collision_shape.shape as CapsuleShape3D;



@onready
var head_standing_position := head.position;
@onready
var head_position := head_standing_position;
@onready
var capsule_height := capsule_shape.height;



var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity");
var mouse_captured := false;
var headbob_time := 0.0;
var is_sliding := false;
var slide_stopped := false;
var view_direction := Vector2.ZERO;
var jump_buffer := 0.0;



func exponential_decay(decay: float, delta: float) -> float:
    return 1.0 - exp  (-decay * delta);



func current_friction() -> float:
    if is_sliding:
        return slide_friction;
    else:
        return walk_friction;



func is_grounded() -> bool:
    if is_sliding:
        return is_on_wall() && get_wall_normal().angle_to(Vector3.UP) < floor_max_angle;
    else:
        return is_on_floor();


func speed() -> float:
    return velocity.length();



func _physics_process(delta: float) -> void: 
    var is_at_slide_speed := get_real_velocity().length() > slide_min_speed;

    if Input.is_action_pressed("slide") && !slide_stopped:
        is_sliding = true;
        motion_mode = MOTION_MODE_FLOATING;
    else:
        is_sliding = false;
        motion_mode = MOTION_MODE_GROUNDED;

    if !is_at_slide_speed && is_grounded():
        slide_stopped = true;

    if !Input.is_action_pressed("slide"):
        slide_stopped = false;

    # get the movement input
    var movement_input := Input.get_vector(
        "move_left", 
        "move_right", 
        "move_forward", 
        "move_back",
      );

    # compute the movement vector
    var movement: Vector3;

    if is_sliding && is_grounded():
        var right := get_wall_normal().cross(transform.basis.z).normalized();
        var forward := get_wall_normal().cross(-right).normalized();

        movement = right * movement_input.x + forward * movement_input.y;
    else:
        movement = transform.basis * Vector3(movement_input.x, 0.0, movement_input.y);

    # the name current speed is somewhat misleading, 
    # in reality it's the speed in the direction of the movement
    var current_speed := movement.dot(velocity); 

    var target_speed: float;
    var acceleration: float;

    if is_grounded():
        if is_sliding:
            target_speed = slide_speed;
            acceleration = slide_acceleration;
        else:
            target_speed = walk_speed;
            acceleration = walk_acceleration;
    else:
        target_speed = air_speed;
        acceleration = air_acceleration;

    var delta_speed := clampf(target_speed - current_speed, 0.0, acceleration * delta);
    var actual_speed := velocity.length();
    var max_speed := maxf(target_speed, actual_speed);
    
    velocity += movement * delta_speed;

    # limit the velocity so we don't gain speed when air strafing
    velocity = velocity.limit_length(max_speed);

    if is_grounded():
        velocity -= velocity * current_friction() * delta;

    velocity.y -= gravity * delta;

    if is_grounded() && jump_buffer > 0.0:
        velocity.y = jump_impulse;
        jump_buffer = 0.0;

    jump_buffer -= delta;
    jump_buffer = max(jump_buffer, 0.0);  

    move_and_slide();

    if is_sliding: 
        velocity = get_real_velocity();



func _process(delta: float) -> void:
    # headbobbing
    var head_target := head_standing_position;

    # update the camera and collision shape when sliding
    if is_sliding && is_grounded():
        head_target.y -= slide_height;
        capsule_shape.height = capsule_height - slide_height;
    else:
        capsule_shape.height = capsule_height;

    collision_shape.transform.origin.y = capsule_shape.height / 2.0;

    head_position = lerp(
        head_position, 
        head_target, 
        exponential_decay(20.0, delta),
    );

    head.position = head_position + headbob(headbob_time);

    # update the camera rotation
    camera.rotation.x = view_direction.x;
    rotation.y = view_direction.y;  

    var forward := -transform.basis.z.dot(get_real_velocity().normalized());
    var right := transform.basis.x.dot(get_real_velocity().normalized());
    var tilt_decay := exponential_decay(15.0, delta);

    if is_sliding && is_grounded():
        head.rotation_degrees.x = lerp(
            head.rotation_degrees.x, 
            slide_head_tilt * forward, 
            tilt_decay,
        );
        head.rotation_degrees.z = lerp(
            head.rotation_degrees.z, 
            slide_head_tilt * right, 
            tilt_decay,
        );
    else:
        head.rotation_degrees.x = lerp(head.rotation_degrees.x, 0.0, tilt_decay);
        head.rotation_degrees.z = lerp(head.rotation_degrees.z, 0.0, tilt_decay);

    # headbob time
    if is_grounded() && !is_sliding:
        headbob_time += min(velocity.length(), walk_speed) * delta;

    var horizontal_velocity := Vector2(velocity.x, velocity.z);

    # fov
    var clamped_speed := clampf(horizontal_velocity.length(), 0.5, walk_speed * 4.0);
    var target_fov := fov + clamped_speed * fov_factor;
    camera.fov = lerp(
        camera.fov, 
        target_fov, 
        exponential_decay(fov_decay, delta),
    );



# compute the offset of the head, for the headbob effect
func headbob(time: float) -> Vector3:
    var bobbing := Vector3.ZERO;

    bobbing.y = sin(time * headbob_frequency) * headbob_amplitude;
    bobbing.x = cos(time * headbob_frequency / 2.0) * headbob_amplitude;

    return bobbing;



# handle input events
func _input(event: InputEvent) -> void:
    match true:
        _ when event is InputEventMouseMotion: mouse_motion_input(event);
        _ when event is InputEventMouseButton: mouse_button_input(event);
        _ when event is InputEventKey:         key_input(event);



# handle mouse motion inputs
func mouse_motion_input(event: InputEventMouseMotion) -> void:
    if !mouse_captured: return;

    view_direction.x -= event.relative.y * view_sensitive * 0.005;
    view_direction.y -= event.relative.x * view_sensitive * 0.005;

    view_direction.x = clamp(
        view_direction.x, 
        deg_to_rad(-view_limit), 
        deg_to_rad(view_limit),
    );



# handle mouse button inputs
func mouse_button_input(event: InputEventMouseButton) -> void:
    if event.is_action_pressed("shoot"):
        if !mouse_captured:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED);
            mouse_captured = true;
            return;

        velocity += camera.global_transform.basis.z * 20.0;

    

# handle key inputs
func key_input(event: InputEventKey) -> void:
    if event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE);
        mouse_captured = false;

    if event.is_action_pressed("jump"):
        jump_buffer = jump_buffer_time;
