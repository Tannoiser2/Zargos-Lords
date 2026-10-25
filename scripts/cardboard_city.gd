class_name CardboardCity
extends StaticBody3D

var faction: StringName
var hex := Vector2i.ZERO
var label: Label3D
var material: StandardMaterial3D
var garrison: Array[CardboardUnit] = []

func setup(p_faction: StringName, p_hex: Vector2i) -> void:
	faction = p_faction
	hex = p_hex
	name = "Citta_%s_%s" % [faction, get_instance_id()]
	_build_mesh()

func _build_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.36
	cylinder.bottom_radius = 0.36
	cylinder.height = 0.13
	cylinder.radial_segments = 6
	material = StandardMaterial3D.new()
	material.albedo_color = ZargosRules.FACTION_COLORS[faction].darkened(0.18)
	material.roughness = 0.8
	cylinder.material = material
	mesh_instance.mesh = cylinder
	add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.36
	shape.height = 0.14
	collision.shape = shape
	add_child(collision)

	label = Label3D.new()
	label.text = "CITTÀ\n%s" % String(faction).to_upper()
	label.font_size = 30
	label.modulate = Color("24160e")
	label.outline_size = 4
	label.outline_modulate = Color(1, 1, 1, 0.62)
	label.position = Vector3(0, 0.072, 0)
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.pixel_size = 0.0055
	add_child(label)

func change_owner(new_faction: StringName) -> void:
	faction = new_faction
	material.albedo_color = ZargosRules.FACTION_COLORS[faction].darkened(0.18)
	label.text = "CITTÀ\n%s" % String(faction).to_upper()

func can_garrison() -> bool:
	return garrison.size() < 4

func add_to_garrison(unit: CardboardUnit) -> bool:
	if not can_garrison() or unit.faction != faction:
		return false
	garrison.append(unit)
	unit.visible = false
	unit.collision_layer = 0
	unit.collision_mask = 0
	_refresh_label()
	return true

func release_first() -> CardboardUnit:
	if garrison.is_empty():
		return null
	var unit: CardboardUnit = garrison.pop_front()
	unit.visible = true
	unit.collision_layer = 1
	unit.collision_mask = 1
	_refresh_label()
	return unit

func garrison_strength() -> int:
	var total := 0
	for unit in garrison:
		total += unit.combat
	return total

func clear_garrison() -> Array[CardboardUnit]:
	var defeated: Array[CardboardUnit] = garrison.duplicate()
	garrison.clear()
	_refresh_label()
	return defeated

func _refresh_label() -> void:
	label.text = "CITTÀ\n%s\nGUARN. %s" % [String(faction).to_upper(), "-" if garrison.is_empty() else "?"]

