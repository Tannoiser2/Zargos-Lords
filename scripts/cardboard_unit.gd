class_name CardboardUnit
extends StaticBody3D

var faction: StringName
var unit_type: StringName
var movement := 0
var combat := 0
var ability := ""
var hex := Vector2i.ZERO
var moved := false
var acted := false
var ranged_hits := 0

const COUNTER_TEXTURES := {
	&"Cavalieri": {
		&"Signore": preload("res://assets/units/cavalieri/signore.png"),
		&"Mago": preload("res://assets/units/cavalieri/mago.png"),
		&"Fantarcere": preload("res://assets/units/cavalieri/fantarcere.png"),
		&"Fante": preload("res://assets/units/cavalieri/fante.png"),
	},
	&"Draghi": {
		&"Signore": preload("res://assets/units/draghi/signore.png"),
		&"Serpente": preload("res://assets/units/draghi/serpente.png"),
		&"Lanciafiamme": preload("res://assets/units/draghi/lanciafiamme.png"),
		&"Fante": preload("res://assets/units/draghi/fante.png"),
	},
	&"Alati": {
		&"Signore": preload("res://assets/units/alati/signore.png"),
		&"Falco": preload("res://assets/units/alati/falco.png"),
		&"Fantarcere": preload("res://assets/units/alati/fantarcere.png"),
		&"Fante": preload("res://assets/units/alati/fante.png"),
	},
	&"Monaci": {
		&"Signore": preload("res://assets/units/monaci/signore.png"),
		&"Illusionista": preload("res://assets/units/monaci/illusionista.png"),
		&"Cavaliere": preload("res://assets/units/monaci/cavaliere.png"),
		&"Fante": preload("res://assets/units/monaci/fante.png"),
	},
}

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
	cylinder.top_radius = 0.22
	cylinder.bottom_radius = 0.22
	cylinder.height = 0.055
	cylinder.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = ZargosRules.FACTION_COLORS[faction]
	material.roughness = 0.86
	cylinder.material = material
	mesh_instance.mesh = cylinder
	add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.22
	shape.height = 0.065
	collision.shape = shape
	add_child(collision)

	var face := MeshInstance3D.new()
	var face_mesh := PlaneMesh.new()
	face_mesh.size = Vector2(0.43, 0.43)
	var face_material := StandardMaterial3D.new()
	face_material.albedo_texture = COUNTER_TEXTURES[faction][unit_type]
	face_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh.material = face_material
	face.mesh = face_mesh
	face.position.y = 0.029
	add_child(face)

func set_selected(value: bool) -> void:
	scale = Vector3.ONE * (1.18 if value else 1.0)

func reset_turn() -> void:
	moved = false
	acted = false
	ranged_hits = 0

