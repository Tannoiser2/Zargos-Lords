class_name ZSegnalino
extends Node3D
## Pedina di cartone tridimensionale: prisma esagonale con la faccia stampata.

const RAGGIO := 0.124
const SPESSORE := 0.042

static var _mesh_cache := {}
static var _mat_cache := {}

var id := -1
var popolo := ""
var tipo := ""
var corpo: MeshInstance3D
var anello: MeshInstance3D
var etichetta: Label3D
var vortice: MeshInstance3D
var _sollevato := 0.0
var _destinazione := Vector3.ZERO
var _tween: Tween

static func mesh_esagono(raggio: float, spessore: float) -> ArrayMesh:
	var k := "%f_%f" % [raggio, spessore]
	if _mesh_cache.has(k):
		return _mesh_cache[k]
	var st := SurfaceTool.new()
	# Faccia superiore, punta in alto come gli esagoni della mappa.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var punti: Array[Vector3] = []
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		punti.append(Vector3(cos(a) * raggio, spessore, sin(a) * raggio))
	var uv_scala := 250.0 / 512.0
	for i in 6:
		var a := punti[i]
		var b := punti[(i + 1) % 6]
		for p in [Vector3(0, spessore, 0), a, b]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5 + p.x / raggio * uv_scala, 0.5 + p.z / raggio * uv_scala))
			st.add_vertex(p)
	var mesh := st.commit()
	# Bordi del cartone.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a := punti[i]
		var b := punti[(i + 1) % 6]
		var a0 := Vector3(a.x, 0, a.z)
		var b0 := Vector3(b.x, 0, b.z)
		var n := ((a + b) * 0.5 * Vector3(1, 0, 1)).normalized()
		for p in [a, b0, b, a, a0, b0]:
			st.set_normal(n)
			st.add_vertex(p)
	st.commit(mesh)
	_mesh_cache[k] = mesh
	return mesh

static func materiale_faccia(percorso: String) -> StandardMaterial3D:
	if _mat_cache.has(percorso):
		return _mat_cache[percorso]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(percorso)
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[percorso] = m
	return m

static func materiale_bordo(colore: Color) -> StandardMaterial3D:
	var k := "bordo_" + colore.to_html()
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = colore
	m.roughness = 0.9
	_mat_cache[k] = m
	return m

func prepara(p_id: int, p_popolo: String, p_tipo: String, citta := false) -> void:
	id = p_id
	popolo = p_popolo
	tipo = p_tipo
	corpo = MeshInstance3D.new()
	var raggio := RAGGIO * (1.08 if citta else 1.0)
	var spessore := SPESSORE * (1.6 if citta else 1.0)
	corpo.mesh = mesh_esagono(raggio, spessore)
	corpo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_imposta_faccia(p_popolo, p_tipo)
	add_child(corpo)
	anello = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = raggio * 1.02
	t.outer_radius = raggio * 1.22
	t.rings = 6
	t.ring_segments = 4
	anello.mesh = t
	anello.rotation.y = deg_to_rad(30)
	var ma := StandardMaterial3D.new()
	ma.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ma.albedo_color = ZTema.OCRA
	anello.material_override = ma
	anello.position.y = 0.01
	anello.visible = false
	add_child(anello)
	etichetta = Label3D.new()
	etichetta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etichetta.font = ZTema.titolo
	etichetta.font_size = 64
	etichetta.pixel_size = 0.0016
	etichetta.outline_size = 14
	etichetta.modulate = ZTema.AVORIO
	etichetta.outline_modulate = ZTema.INCHIOSTRO
	etichetta.position = Vector3(0, spessore + 0.11, 0)
	etichetta.no_depth_test = true
	etichetta.visible = false
	add_child(etichetta)

func _imposta_faccia(p_popolo: String, p_tipo: String) -> void:
	popolo = p_popolo
	corpo.set_surface_override_material(0, materiale_faccia("res://assets/units/%s/%s.png" % [p_popolo.to_lower(), p_tipo]))
	corpo.set_surface_override_material(1, materiale_bordo(ZRegole.COLORI[p_popolo].darkened(0.35)))

func cambia_popolo(p: String) -> void:
	if p != popolo:
		_imposta_faccia(p, tipo)

func seleziona(attivo: bool, colore: Color = ZTema.OCRA) -> void:
	anello.visible = attivo
	(anello.material_override as StandardMaterial3D).albedo_color = colore
	_sollevato = 0.05 if attivo else 0.0
	corpo.position.y = _sollevato

func testo(t: String, colore := ZTema.AVORIO) -> void:
	etichetta.visible = t != ""
	etichetta.text = t
	etichetta.modulate = colore

func paralizzato(attivo: bool) -> void:
	if attivo and vortice == null:
		vortice = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.06
		t.outer_radius = 0.09
		vortice.mesh = t
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.85, 0.25, 0.9, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vortice.material_override = m
		vortice.position.y = SPESSORE + 0.02
		add_child(vortice)
	if vortice:
		vortice.visible = attivo

func _process(delta: float) -> void:
	if vortice and vortice.visible:
		vortice.rotate_y(delta * 2.5)

## Sposta la pedina con un piccolo balzo, come se la si sollevasse dal tavolo.
func vai_a(pos: Vector3, durata := 0.25) -> void:
	_destinazione = pos
	if _tween:
		_tween.kill()
	if durata <= 0.0 or position.distance_to(pos) < 0.001:
		position = pos
		return
	var da := position
	var altezza := clampf(da.distance_to(pos) * 0.25, 0.08, 0.6)
	_tween = create_tween()
	_tween.tween_method(func(t: float):
		var p := da.lerp(pos, t)
		p.y += sin(t * PI) * altezza
		position = p
	, 0.0, 1.0, durata).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func elimina_animato() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", position.y + 0.25, 0.2)
	_tween.parallel().tween_property(self, "scale", Vector3(0.2, 0.2, 0.2), 0.35).set_delay(0.1)
	_tween.tween_callback(queue_free)
