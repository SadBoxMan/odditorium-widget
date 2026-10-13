extends RigidBody2D
## One flung object: reports collisions, fades out at the end of its
## lifetime (or when it leaves the screen far behind) and frees itself.

## Emitted for every body this object starts touching.
signal hit(body: RigidBody2D, other: Node)

var _life := 4.0
var _fade := 0.6
var _age := 0.0
## Set by the module once this object has bonked the cam region.
var bonked := false
var _label: Label


func setup(lifetime_s: float, fade_s: float, label_text: String) -> void:
	_life = lifetime_s
	_fade = minf(fade_s, lifetime_s)
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body_entered.connect(_on_body_entered)
	if label_text != "":
		_label = Label.new()
		_label.text = label_text
		_label.top_level = true  # don't spin with the body
		_label.add_theme_color_override("font_color", Color.WHITE)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 5)
		_label.add_theme_font_size_override("font_size", 18)
		add_child(_label)


func _physics_process(delta: float) -> void:
	_age += delta
	if _label:
		_label.global_position = global_position + Vector2(-_label.size.x * 0.5, -60)
	if _age >= _life - _fade:
		modulate.a = clampf((_life - _age) / maxf(_fade, 0.001), 0.0, 1.0)
	if _age >= _life or global_position.y > 5000.0 or absf(global_position.x) > 8000.0:
		queue_free()


func _on_body_entered(other: Node) -> void:
	hit.emit(self, other)
