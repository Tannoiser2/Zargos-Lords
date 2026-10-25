class_name CardboardUnit
extends StaticBody3D

var faction: StringName
var unit_type: StringName
var movement := 0
var combat := 0
var ability := ""
var hex := Vector2i.ZERO
var moved := false

func setup(p_faction: StringName, p_type: StringName, p_hex: Vector2i) -> void:
	faction = p_faction
	unit_type = p_type
	hex = p_hex
	var stats: Dictionary = ZargosRules.UNIT_TYPES[faction][unit_type]
	movement = stats.move
	combat = stats.combat
	ability = stats.ability
	name = "%s_%s_%s" % [faction, unit_type, get_instance_id()]
	_build_mesh()

func _build_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.30
	cylinder.bottom_radius = 0.30
	cylinder.height = 0.075
	cylinder.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = ZargosRules.FACTION_COLORS[faction]
	material.roughness = 0.86
	cylinder.material = material
	mesh_instance.mesh = cylinder
	add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.30
	shape.height = 0.09
	collision.shape = shape
	add_child(collision)

	var label := Label3D.new()
	label.text = "%s\n%d · %d" % [String(unit_type).left(4).to_upper(), movement, combat]
	label.font_size = 34
	label.modulate = Color("23180e")
	label.outline_size = 3
	label.outline_modulate = Color(1, 1, 1, 0.55)
	label.position = Vector3(0, 0.044, 0)
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.pixel_size = 0.0062
	label.no_depth_test = false
	add_child(label)

func set_selected(value: bool) -> void:
	scale = Vector3.ONE * (1.18 if value else 1.0)

