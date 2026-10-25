class_name CardboardCity
extends StaticBody3D

var faction: StringName
var hex := Vector2i.ZERO
var label: Label3D
var material: StandardMaterial3D
var face_material: StandardMaterial3D
var garrison: Array[CardboardUnit] = []

const CITY_TEXTURES := {
	&"Cavalieri": preload("res://assets/units/cavalieri/citta.png"),
	&"Draghi": preload("res://assets/units/draghi/citta.png"),
	&"Alati": preload("res://assets/units/alati/citta.png"),
	&"Monaci": preload("res://assets/units/monaci/citta.png"),
}

func setup(p_faction: StringName, p_hex: Vector2i) -> void:
	faction = p_faction
	hex = p_hex
	name = "Citta_%s_%s" % [faction, get_instance_id()]
	_build_mesh()

func _build_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.23
	cylinder.bottom_radius = 0.23
	cylinder.height = 0.065
	cylinder.radial_segments = 6
	material = StandardMaterial3D.new()
	material.albedo_color = ZargosRules.FACTION_COLORS[faction].darkened(0.18)
	material.roughness = 0.8
	cylinder.material = material
	mesh_instance.mesh = cylinder
	add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.23
	shape.height = 0.075
	collision.shape = shape
	add_child(collision)

	var face := MeshInstance3D.new()
	var face_mesh := PlaneMesh.new()
	face_mesh.size = Vector2(0.45, 0.45)
	face_material = StandardMaterial3D.new()
	face_material.albedo_texture = CITY_TEXTURES[faction]
	face_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh.material = face_material
	face.mesh = face_mesh
	face.position.y = 0.034
	add_child(face)

	label = Label3D.new()
	label.visible = false
	add_child(label)

func change_owner(new_faction: StringName) -> void:
	faction = new_faction
	material.albedo_color = ZargosRules.FACTION_COLORS[faction].darkened(0.18)
	face_material.albedo_texture = CITY_TEXTURES[faction]

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
	pass

