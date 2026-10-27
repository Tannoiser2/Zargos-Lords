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
	etichetta.position = Vector3(0, spessore + (ALTEZZA_MODELLO + 0.06 if _figura else 0.11), 0)
	etichetta.no_depth_test = true
	etichetta.visible = false
	add_child(etichetta)

static func percorso_faccia(p_popolo: String, t: String) -> String:
	# Con le miniature 3D la pedina diventa una base con i soli valori.
	if ZTema.grafica == "3d" and t not in ["retro", "scomparso"] and ZTema.percorso_modello(p_popolo, t) != "":
		var base := "res://assets/units_basi/%s/%s.png" % ["magia" if t == "megadrago" else p_popolo.to_lower(), t]
		if ResourceLoader.exists(base):
			return base
	match t:
		"retro": return "res://assets/units/retro.png"
		"megadrago": return "res://assets/units/magia/megadrago.png"
	return ZTema.percorso_pedina(p_popolo, t)

# --- Miniature 3D ----------------------------------------------------------------

const ALTEZZA_MODELLO := 0.26
static var _modelli := {}   # percorso -> {"scena", "scala", "centro"}
var _figura: Node3D
var _figura_tipo := ""

static func _dati_modello(percorso: String) -> Dictionary:
	if _modelli.has(percorso):
		return _modelli[percorso]
	var scena: PackedScene = load(percorso)
	var d := {"scena": scena, "scala": 1.0, "centro": Vector3.ZERO}
	if scena:
		var n := scena.instantiate()
		var box := AABB()
		var primo := true
		var punti := PackedVector3Array()
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var t := Transform3D.IDENTITY
			var x: Node = m
			while x != null and x != n:
				if x is Node3D:
					t = (x as Node3D).transform * t
				x = x.get_parent()
			var b := t * m.get_aabb()
			if m.mesh:
				for k in m.mesh.get_surface_count():
					for v in m.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
						punti.append(t * v)
			box = b if primo else box.merge(b)
			primo = false
		n.free()
		if not primo and box.size.y > 0.0:
			var s := ALTEZZA_MODELLO / box.size.y
			# Le figure larghe (ragno, serpente, cammello) non escono dall'esagono.
			s = minf(s, RAGGIO * 2.6 / maxf(box.size.x, box.size.z))
			if percorso.ends_with("citta.glb"):
				# La città resta dentro la sua base esagonale (raggio inscritto).
				s = minf(ALTEZZA_MODELLO * 1.1 / box.size.y, RAGGIO * 1.08 * 0.866 * 2.0 / maxf(box.size.x, box.size.z))
			d.scala = s
			d.centro = Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
			# Centra la miniatura sui punti d'appoggio (piedi, zampe), non sulle armi sporgenti.
			var soglia := box.position.y + box.size.y * 0.12
			var somma := Vector3.ZERO
			var conta := 0
			for v in punti:
				if v.y <= soglia:
					somma += v
					conta += 1
			if conta > 20 and not percorso.ends_with("citta.glb"):
				d.centro = Vector3(somma.x / conta, box.position.y, somma.z / conta)
	_modelli[percorso] = d
	return d

## Mostra (o toglie) la miniatura sopra la pedina.
func figura(t: String) -> void:
	var percorso := ""
	if ZTema.grafica == "3d" and t not in ["retro", "scomparso"]:
		percorso = ZTema.percorso_modello(popolo, t)
	if percorso == _figura_tipo:
		return
	_figura_tipo = percorso
	if _figura:
		_figura.queue_free()
		_figura = null
		if etichetta:
			etichetta.position.y = SPESSORE * (1.6 if tipo == "citta" else 1.0) + 0.11
	if percorso == "":
		return
	var d := _dati_modello(percorso)
	if d.scena == null:
		return
	_figura = Node3D.new()
	var n: Node3D = d.scena.instantiate()
	var sc: float = d.scala * (1.35 if t == "megadrago" else 1.0)
	if t == "citta":
		# Le città sono più larghe e restano dentro il loro esagono.
		sc = d.scala
	n.scale = Vector3.ONE * sc
	n.position = -d.centro * sc
	_figura.add_child(n)
	var sp := SPESSORE * (1.6 if tipo == "citta" else 1.0)
	_figura.position.y = sp
	if etichetta:
		etichetta.position.y = sp + ALTEZZA_MODELLO + 0.06
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	corpo.add_child(_figura)
	_grigia_figura()

func _imposta_faccia(p_popolo: String, p_tipo: String) -> void:
	popolo = p_popolo
	_faccia_attuale = p_tipo
	_applica_materiali()
	figura(p_tipo)

# --- Pezzi ridotti: tutto grigio, come pietrificato ----------------------------------

const SHADER_GRIGIO := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 base : source_color = vec4(1.0);
uniform bool usa_tex = true;
void fragment() {
	vec4 c = usa_tex ? texture(tex, UV) : base;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = vec3(g * 0.6 + 0.12);
	ROUGHNESS = 0.95;
}
"""
static var _shader_grigio: Shader
var _grigio := false

static func materiale_grigio(tex: Texture2D, colore := Color.WHITE) -> ShaderMaterial:
	var k := "grigio_%d_%s" % [tex.get_instance_id() if tex else 0, colore.to_html()]
	if _mat_cache.has(k):
		return _mat_cache[k]
	if _shader_grigio == null:
		_shader_grigio = Shader.new()
		_shader_grigio.code = SHADER_GRIGIO
	var m := ShaderMaterial.new()
	m.shader = _shader_grigio
	m.set_shader_parameter("usa_tex", tex != null)
	if tex:
		m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("base", colore)
	_mat_cache[k] = m
	return m

func _applica_materiali() -> void:
	var percorso := percorso_faccia(popolo, _faccia_attuale)
	if _grigio:
		corpo.set_surface_override_material(0, materiale_grigio(load(percorso)))
		corpo.set_surface_override_material(1, materiale_bordo(Color(0.42, 0.42, 0.42)))
	else:
		corpo.set_surface_override_material(0, materiale_faccia(percorso))
		corpo.set_surface_override_material(1, materiale_bordo(ZRegole.COLORI[popolo].darkened(0.35)))
	_grigia_figura()

func _grigia_figura() -> void:
	if _figura == null:
		return
	for mi in _figura.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not _grigio:
			m.material_override = null
			continue
		var tex: Texture2D = null
		var col := Color.WHITE
		var orig := m.get_active_material(0)
		if orig is StandardMaterial3D:
			tex = (orig as StandardMaterial3D).albedo_texture
			col = (orig as StandardMaterial3D).albedo_color
		m.material_override = materiale_grigio(tex, col)

## Pezzo ridotto: pedina e miniatura grigie e ferme.
func grigio(attivo: bool) -> void:
	if attivo == _grigio:
		return
	_grigio = attivo
	_applica_materiali()

var _faccia_attuale := ""

func faccia(t: String) -> void:
	if t != _faccia_attuale:
		_faccia_attuale = t
		figura(t)
		_applica_materiali()

func cambia_popolo(p: String) -> void:
	if p != popolo:
		_imposta_faccia(p, tipo)

## Contorno pulsante per gli effetti in corso (Spada di luce, rete).
var _alone: MeshInstance3D
func alone(colore: Color) -> void:
	if colore.a <= 0.0:
		if _alone:
			_alone.visible = false
		return
	if _alone == null:
		_alone = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = RAGGIO * 0.98
		t.outer_radius = RAGGIO * 1.1
		t.rings = 6
		t.ring_segments = 4
		_alone.mesh = t
		_alone.rotation.y = deg_to_rad(30)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_alone.material_override = m
		_alone.position.y = SPESSORE * 0.5
		add_child(_alone)
	_alone.visible = true
	(_alone.material_override as StandardMaterial3D).albedo_color = colore

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

## Il tiratore si volta verso il bersaglio e si "carica" all'indietro.
func carica_tiro(bersaglio: Vector3) -> void:
	var dir := bersaglio - position
	dir.y = 0
	var tw := create_tween()
	if _figura and dir.length() > 0.001:
		var ang := atan2(dir.x, dir.z)
		tw.tween_property(_figura, "rotation:y", ang, 0.25).set_trans(Tween.TRANS_SINE)
	var dietro := -dir.normalized() * 0.025 if dir.length() > 0.001 else Vector3.ZERO
	tw.tween_property(corpo, "position", Vector3(dietro.x, _sollevato + 0.02, dietro.z), 0.15)
	tw.tween_property(corpo, "position", Vector3(-dietro.x * 0.6, _sollevato, -dietro.z * 0.6), 0.08)
	tw.tween_property(corpo, "position", Vector3(0, _sollevato, 0), 0.15)
	await get_tree().create_timer(0.4).timeout

## Sussulto del bersaglio colpito.
func sussulta() -> void:
	var tw := create_tween()
	for k in 4:
		var x := 0.012 * (1 if k % 2 == 0 else -1)
		tw.tween_property(corpo, "position:x", x, 0.04)
	tw.tween_property(corpo, "position:x", 0.0, 0.04)
