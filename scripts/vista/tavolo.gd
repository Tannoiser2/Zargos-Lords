class_name ZTavolo
extends Node3D
## Il tavolo da gioco in 3D: tabellone, pedine, città, evidenziazioni,
## telecamera orbitale e selezione degli esagoni col mouse.

signal esagono_cliccato(h: Vector2i, shift: bool)
signal esagono_destro(h: Vector2i)
signal esagono_sopra(h: Vector2i)

const SCALA := 256.0  # pixel della mappa per unità del mondo

var mappa: ZMappa
var camera: Camera3D
var segnalini := {}       # id pedina -> ZSegnalino
var citta := {}           # id città -> ZSegnalino
var _overlay := {}        # nome -> MultiMeshInstance3D
var _griglia: MeshInstance3D
var _sopra: MeshInstance3D
var _esagono_sopra := Vector2i(-1, -1)
var _yaw := 0.0
var _pitch := deg_to_rad(-62.0)
var _distanza := 10.0
var _centro := Vector3.ZERO
var _yaw_obiettivo := 0.0
var _pitch_obiettivo := deg_to_rad(-62.0)
var _distanza_obiettivo := 10.0
var _centro_obiettivo := Vector3.ZERO
var _trascina_sx := false
var _trascina_dx := false
var _trascina_centro := false
var _premuto_in := Vector2.ZERO
var _spostato := false
var effetti: Node3D
var _materiale_mappa: StandardMaterial3D

## "nuova" = mappa della nuova edizione (TTS); "originale" = tabellone 1979,
## riallineato sul reticolo della nuova.
func usa_mappa(quale: String) -> void:
	var percorso := "res://assets/board/mappa_originale.jpg" if quale == "originale" else "res://assets/board/mappa.png"
	if ResourceLoader.exists(percorso):
		_materiale_mappa.albedo_texture = load(percorso)

func _ready() -> void:
	mappa = ZMappa.condivisa()
	_costruisci_ambiente()
	_costruisci_tavolo()
	_costruisci_griglia()
	_sopra = _anello_esagono(Color(1, 0.95, 0.75, 0.9), 0.012)
	_sopra.visible = false
	add_child(_sopra)
	for nome in ["raggio", "bersagli", "basi", "schieramento", "gittata", "gruppo"]:
		_crea_overlay(nome)
	effetti = Node3D.new()
	add_child(effetti)
	camera = Camera3D.new()
	camera.fov = 40
	camera.near = 0.05
	camera.far = 120
	add_child(camera)
	inquadra(Vector3.ZERO, 11.5, true)

# --- Coordinate ----------------------------------------------------------------

func mondo(h: Vector2i) -> Vector3:
	var p := mappa.centro_px(h)
	return Vector3(p.x / SCALA - mappa.dimensione_px.x / SCALA * 0.5, 0.0, p.y / SCALA - mappa.dimensione_px.y / SCALA * 0.5)

func esagono_da_mondo(p: Vector3) -> Vector2i:
	var px := Vector2((p.x + mappa.dimensione_px.x / SCALA * 0.5) * SCALA, (p.z + mappa.dimensione_px.y / SCALA * 0.5) * SCALA)
	return mappa.esagono_da_px(px)

func esagono_sotto(schermo: Vector2) -> Vector2i:
	var o := camera.project_ray_origin(schermo)
	var d := camera.project_ray_normal(schermo)
	if absf(d.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := -o.y / d.y
	if t < 0:
		return Vector2i(-1, -1)
	var h := esagono_da_mondo(o + d * t)
	return h if mappa.dentro(h) and mappa.terreno(h) != ZMappa.T.VUOTO else Vector2i(-1, -1)

# --- Costruzione della scena -------------------------------------------------------

func _costruisci_ambiente() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1a0f0a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f3e6d0")
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = false
	we.environment = env
	add_child(we)
	var sole := DirectionalLight3D.new()
	sole.rotation_degrees = Vector3(-55, -35, 0)
	sole.light_color = Color("ffe2b8")
	sole.light_energy = 0.6
	sole.shadow_enabled = true
	sole.shadow_blur = 1.5
	sole.directional_shadow_max_distance = 30
	add_child(sole)
	var lampada := OmniLight3D.new()
	lampada.position = Vector3(0, 7, 0)
	lampada.light_color = Color("ffcf8a")
	lampada.light_energy = 0.0
	lampada.visible = false
	lampada.omni_range = 20
	lampada.omni_attenuation = 1.4
	add_child(lampada)

func _costruisci_tavolo() -> void:
	var w := mappa.dimensione_px.x / SCALA
	var hgt := mappa.dimensione_px.y / SCALA
	# Piano del tavolo in legno scuro.
	var tavolo := MeshInstance3D.new()
	var piano := PlaneMesh.new()
	piano.size = Vector2(60, 60)
	tavolo.mesh = piano
	var mt := StandardMaterial3D.new()
	var rumore := FastNoiseLite.new()
	rumore.frequency = 0.004
	rumore.fractal_octaves = 4
	rumore.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.noise = rumore
	tex.seamless = true
	var grad := Gradient.new()
	grad.set_color(0, Color("2a170e"))
	grad.set_color(1, Color("4a2a18"))
	tex.color_ramp = grad
	mt.albedo_texture = tex
	mt.uv1_scale = Vector3(6, 6, 6)
	mt.roughness = 0.7
	tavolo.material_override = mt
	tavolo.position.y = -0.06
	add_child(tavolo)
	# Tabellone in cartone spesso.
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w + 0.12, 0.05, hgt + 0.12)
	base.mesh = box
	var mb := StandardMaterial3D.new()
	mb.albedo_color = Color("15100d")
	mb.roughness = 0.6
	base.material_override = mb
	base.position.y = -0.026
	add_child(base)
	var faccia := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, hgt)
	faccia.mesh = pm
	var mf := StandardMaterial3D.new()
	_materiale_mappa = mf
	mf.albedo_texture = load("res://assets/board/mappa.png")
	mf.roughness = 0.9
	mf.albedo_color = Color(0.9, 0.88, 0.85)
	mf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	faccia.material_override = mf
	faccia.position.y = 0.0
	faccia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(faccia)

func _costruisci_griglia() -> void:
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.95, 0.8, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	var r := mappa.raggio_px / SCALA
	for riga in mappa.righe:
		for col in mappa.colonne:
			var h := Vector2i(col, riga)
			if not mappa.terra(h):
				continue
			var c := mondo(h) + Vector3(0, 0.004, 0)
			for i in 6:
				var a := deg_to_rad(60.0 * i - 90.0)
				var b := deg_to_rad(60.0 * (i + 1) - 90.0)
				im.surface_add_vertex(c + Vector3(cos(a), 0, sin(a)) * r)
				im.surface_add_vertex(c + Vector3(cos(b), 0, sin(b)) * r)
	im.surface_end()
	_griglia = MeshInstance3D.new()
	_griglia.mesh = im
	_griglia.visible = false
	add_child(_griglia)

func mostra_griglia(v: bool) -> void:
	_griglia.visible = v

func griglia_visibile() -> bool:
	return _griglia.visible

func _mesh_esagono_piatto(raggio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		var b := deg_to_rad(60.0 * (i + 1) - 90.0)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(b), 0, sin(b)) * raggio)
		st.add_vertex(Vector3(cos(a), 0, sin(a)) * raggio)
	return st.commit()

func _anello_esagono(colore: Color, spessore: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := mappa.raggio_px / SCALA
	var ri := r - spessore * 2.2
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		var b := deg_to_rad(60.0 * (i + 1) - 90.0)
		var ea := Vector3(cos(a), 0, sin(a))
		var eb := Vector3(cos(b), 0, sin(b))
		for p in [ea * ri, eb * r, ea * r, ea * ri, eb * ri, eb * r]:
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colore
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _crea_overlay(nome: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_overlay[nome] = mi

## Colora un insieme di esagoni. `colore` può essere un Color unico o un
## dizionario esagono -> Color.
func evidenzia(nome: String, esagoni: Array, colore: Variant) -> void:
	var im: ImmediateMesh = _overlay[nome].mesh
	im.clear_surfaces()
	if esagoni.is_empty():
		return
	var quota := {"raggio": 0.003, "schieramento": 0.002, "gittata": 0.0035, "basi": 0.004, "bersagli": 0.005, "gruppo": 0.0025}
	var r := mappa.raggio_px / SCALA * 0.92
	var bordo := mappa.raggio_px / SCALA * 0.8
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in esagoni:
		var c: Color = colore[h] if colore is Dictionary else colore
		var centro: Vector3 = mondo(h) + Vector3(0, quota.get(nome, 0.003), 0)
		var interno := c
		var orlo := Color(c.darkened(0.6), minf(1.0, c.a * 2.0))
		for i in 6:
			var a := deg_to_rad(60.0 * i - 90.0)
			var b := deg_to_rad(60.0 * (i + 1) - 90.0)
			var ea := Vector3(cos(a), 0, sin(a))
			var eb := Vector3(cos(b), 0, sin(b))
			# Centro più tenue, bordo pieno: si legge la mappa sotto.
			for v in [[Vector3.ZERO, interno], [ea * bordo, interno], [eb * bordo, interno], [ea * bordo, orlo], [ea * r, orlo], [eb * r, orlo], [ea * bordo, orlo], [eb * r, orlo], [eb * bordo, orlo]]:
				im.surface_set_color(v[1])
				im.surface_add_vertex(centro + v[0])
	im.surface_end()

func pulisci_evidenziazioni(tranne: Array = []) -> void:
	for nome in _overlay:
		if nome not in tranne:
			(_overlay[nome].mesh as ImmediateMesh).clear_surfaces()

# --- Pedine ---------------------------------------------------------------------

func _posizione_pedina(g: ZPartita, u: ZPedina) -> Vector3:
	var p := mondo(u.hex)
	if u.scorta >= 0:
		p.y += ZSegnalino.SPESSORE   # il fante di scorta sta sopra, un po' spostato
		p += Vector3(0.028, 0, 0.028)
	elif u.scortato_da < 0 and not u.scomparso:
		# Zargo's Lords 2: due pezzi nello stesso esagono, impilati e sfalsati.
		var pila := g.pedine_in(u.hex).filter(func(w): return w.scorta < 0 and w.scortato_da < 0 and not w.scomparso)
		var i := pila.find(u)
		if i > 0:
			p.y += ZSegnalino.SPESSORE * i
			p += Vector3(0.035, 0, 0.035) * i
	if u.scomparso and not g.pedine_in(u.hex).is_empty():
		# Segnalino di sparizione sotto un pezzo arrivato dopo: lo si sposta di lato.
		p += Vector3(-0.07, -0.002, -0.05)
	return p

## Allinea la scena allo stato della partita. Le pedine che hanno cambiato
## esagono vengono animate, quelle eliminate scompaiono.
func sincronizza(g: ZPartita, durata := 0.25) -> void:
	var visti := {}
	for u in g.pedine:
		if not u.viva or not u.schierata or u.citta >= 0:
			continue
		visti[u.id] = true
		var s: ZSegnalino = segnalini.get(u.id)
		var pos := _posizione_pedina(g, u)
		if s == null:
			s = ZSegnalino.new()
			add_child(s)
			s.prepara(u.id, u.popolo, u.tipo)
			s.position = pos
			segnalini[u.id] = s
		else:
			s.vai_a(pos, durata)
		s.visible = true
		s.paralizzato(u.paralisi > 0)
		if u.scomparso:
			# Al posto del Signore Monaco resta il segnalino di sparizione.
			s.faccia("scomparso")
			s.scale = Vector3.ONE * 0.75
			s.testo("")
		elif u.ridotta:
			# Pezzo ridotto: girato a faccia in giù, come sul tavolo.
			s.faccia("retro")
			s.scale = Vector3.ONE
			s.testo("")
		else:
			s.faccia(u.tipo)
			s.scale = Vector3.ONE
			s.testo(str(u.paralisi) if u.paralisi > 0 else "", Color(0.95, 0.6, 1.0))
		if u.spada >= g.turno_globale:
			s.alone(Color(1.0, 0.95, 0.6))
		elif u.catturata or (g.zl2() and g.ha_rete(u.hex) and u.popolo != "Aracnidi"):
			s.alone(Color(0.85, 0.85, 0.8, 0.9))
		elif u.muta >= g.turno_globale:
			s.alone(Color(0.75, 0.3, 0.6))
		else:
			s.alone(Color(0, 0, 0, 0))
	for id in segnalini.keys():
		if not visti.has(id):
			var s: ZSegnalino = segnalini[id]
			segnalini.erase(id)
			if g.pedine[id].viva:
				s.queue_free()   # entrato in città: sparisce senza effetti
			else:
				s.elimina_animato()
	_aggiorna_segni(g)
	for ci in g.citta:
		if ci.h[0] < 0:
			if citta.has(ci.id):
				citta[ci.id].queue_free()
				citta.erase(ci.id)
			continue
		var s: ZSegnalino = citta.get(ci.id)
		var pos := mondo(g.hex_citta(ci))
		if s == null:
			s = ZSegnalino.new()
			add_child(s)
			s.prepara(-1, ci.p, "citta", true)
			s.position = pos
			citta[ci.id] = s
		else:
			s.vai_a(pos, durata)
			s.cambia_popolo(ci.p)
		s.testo("" if ci.g.is_empty() else str(ci.g.size()), ZTema.AVORIO)

## Segni sul tavolo di Zargo's Lords 2: reti dei ragni, ponti di pensiero,
## varchi della Grande frana.
var _segni: Node3D
func _aggiorna_segni(g: ZPartita) -> void:
	if _segni:
		_segni.queue_free()
	_segni = Node3D.new()
	add_child(_segni)
	var tex_rete: Texture2D = load("res://assets/units/aracnidi/rete.png")
	for r in g.reti:
		var sp := Sprite3D.new()
		sp.texture = tex_rete
		sp.pixel_size = (mappa.raggio_px / SCALA * 1.5) / tex_rete.get_width()
		sp.axis = Vector3.AXIS_Y
		sp.rotation.y = deg_to_rad(30)
		sp.modulate = Color(1, 1, 1, 0.8)
		sp.position = mondo(Vector2i(int(r[0]), int(r[1]))) + Vector3(0, 0.006, 0)
		_segni.add_child(sp)
	for pt in g.ponti_temp:
		var a := mondo(Vector2i(int(pt[0][0]), int(pt[0][1])))
		var b := mondo(Vector2i(int(pt[1][0]), int(pt[1][1])))
		var f := _freccia(a, b, Color(0.7, 0.9, 1.0, 0.85))
		_segni.add_child(f)
		var f2 := _freccia(b, a, Color(0.7, 0.9, 1.0, 0.85))
		_segni.add_child(f2)
	var varchi: Array = []
	for k in g.terreno_mod:
		var xy: PackedStringArray = String(k).split(",")
		varchi.append(Vector2i(int(xy[0]), int(xy[1])))
	if not _overlay.has("varchi"):
		_crea_overlay("varchi")
	evidenzia("varchi", varchi, Color(0.85, 0.65, 0.35, 0.45))

func segnalino(id: int) -> ZSegnalino:
	return segnalini.get(id)

func seleziona_pedine(ids: Array, colore := ZTema.OCRA) -> void:
	for id in segnalini:
		segnalini[id].seleziona(id in ids, colore)

# --- Effetti ----------------------------------------------------------------------

## Proiettile (freccia, vampa o visione) che vola da un esagono all'altro.
func lancia(da: Vector2i, a: Vector2i, tipo: String) -> void:
	var p := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	match tipo:
		"frecce":
			var c := CylinderMesh.new()
			c.top_radius = 0.004
			c.bottom_radius = 0.004
			c.height = 0.16
			p.mesh = c
			m.albedo_color = Color("f3e6c4")
		"fiamme":
			var s := SphereMesh.new()
			s.radius = 0.05
			s.height = 0.1
			p.mesh = s
			m.albedo_color = Color(1.0, 0.45, 0.1, 0.9)
		_:
			var s := SphereMesh.new()
			s.radius = 0.045
			s.height = 0.09
			p.mesh = s
			m.albedo_color = Color(0.75, 0.55, 1.0, 0.8)
	p.material_override = m
	effetti.add_child(p)
	var o := mondo(da) + Vector3(0, 0.15, 0)
	var f := mondo(a) + Vector3(0, 0.08, 0)
	p.position = o
	if tipo == "frecce":
		p.look_at_from_position(o, f, Vector3.UP)
		p.rotate_object_local(Vector3.RIGHT, PI / 2)
	var tw := create_tween()
	var altezza := o.distance_to(f) * 0.25
	tw.tween_method(func(t: float):
		var q := o.lerp(f, t)
		q.y += sin(t * PI) * altezza
		p.position = q
		if tipo != "frecce":
			p.scale = Vector3.ONE * (1.0 + sin(t * PI * 6.0) * 0.2)
	, 0.0, 1.0, 0.45)
	tw.tween_property(p, "scale", Vector3.ONE * 2.2, 0.15)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(p.queue_free)

func lampo(h: Vector2i, colore := Color(1, 0.9, 0.5)) -> void:
	var anello := _anello_esagono(colore, 0.02)
	anello.position = mondo(h) + Vector3(0, 0.02, 0)
	effetti.add_child(anello)
	var tw := create_tween()
	tw.tween_property(anello, "scale", Vector3(1.8, 1, 1.8), 0.45)
	tw.parallel().tween_property(anello.material_override, "albedo_color:a", 0.0, 0.45)
	tw.tween_callback(anello.queue_free)

# --- Telecamera e input -------------------------------------------------------------

func inquadra(punto: Vector3, distanza := -1.0, subito := false) -> void:
	_centro_obiettivo = punto
	if distanza > 0:
		_distanza_obiettivo = distanza
	if subito:
		_centro = _centro_obiettivo
		_distanza = _distanza_obiettivo
		_aggiorna_camera()

func inquadra_esagoni(lista: Array[Vector2i]) -> void:
	if lista.is_empty():
		return
	var somma := Vector3.ZERO
	for h in lista:
		somma += mondo(h)
	inquadra(somma / lista.size(), 6.5)

func _aggiorna_camera() -> void:
	var dir := Vector3(0, 0, 1).rotated(Vector3.RIGHT, _pitch).rotated(Vector3.UP, _yaw)
	camera.position = _centro + dir * _distanza
	camera.look_at(_centro, Vector3.UP)

func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta * 10.0)
	_centro = _centro.lerp(_centro_obiettivo, k)
	_distanza = lerpf(_distanza, _distanza_obiettivo, k)
	_yaw = lerp_angle(_yaw, _yaw_obiettivo, k)
	_pitch = lerpf(_pitch, _pitch_obiettivo, k)
	_aggiorna_camera()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var b := ev as InputEventMouseButton
		match b.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if b.pressed:
					_distanza_obiettivo = clampf(_distanza_obiettivo * 0.88, 1.6, 16.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if b.pressed:
					_distanza_obiettivo = clampf(_distanza_obiettivo * 1.13, 1.6, 16.0)
			MOUSE_BUTTON_LEFT:
				if b.pressed:
					_trascina_sx = true
					_spostato = false
					_premuto_in = b.position
				else:
					_trascina_sx = false
					if not _spostato:
						var h := esagono_sotto(b.position)
						if h.x >= 0:
							esagono_cliccato.emit(h, b.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if b.pressed:
					_trascina_dx = true
					_spostato = false
					_premuto_in = b.position
				else:
					_trascina_dx = false
					if not _spostato:
						esagono_destro.emit(esagono_sotto(b.position))
			MOUSE_BUTTON_MIDDLE:
				_trascina_centro = b.pressed
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if (_trascina_sx or _trascina_dx) and mm.position.distance_to(_premuto_in) > 6:
			_spostato = true
		if _trascina_dx and _spostato:
			_yaw_obiettivo -= mm.relative.x * 0.006
			_pitch_obiettivo = clampf(_pitch_obiettivo - mm.relative.y * 0.005, deg_to_rad(-88), deg_to_rad(-25))
		elif (_trascina_sx and _spostato) or _trascina_centro:
			var fattore := _distanza * 0.0011
			var destra := camera.global_transform.basis.x
			var avanti := Vector3(destra.z, 0, -destra.x)
			_centro_obiettivo -= (destra * mm.relative.x - avanti * mm.relative.y) * fattore
			_centro_obiettivo.x = clampf(_centro_obiettivo.x, -8.5, 8.5)
			_centro_obiettivo.z = clampf(_centro_obiettivo.z, -6, 6)
			_centro = _centro_obiettivo
		else:
			var h := esagono_sotto(mm.position)
			if h != _esagono_sopra:
				_esagono_sopra = h
				_sopra.visible = h.x >= 0
				if h.x >= 0:
					_sopra.position = mondo(h) + Vector3(0, 0.007, 0)
				esagono_sopra.emit(h)
	elif ev is InputEventMagnifyGesture:
		_distanza_obiettivo = clampf(_distanza_obiettivo / (ev as InputEventMagnifyGesture).factor, 1.6, 16.0)
	elif ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		var destra := camera.global_transform.basis.x
		var avanti := Vector3(destra.z, 0, -destra.x)
		_centro_obiettivo += (destra * pg.delta.x - avanti * pg.delta.y) * _distanza * 0.02

func ruota_vista(gradi: float) -> void:
	_yaw_obiettivo += deg_to_rad(gradi)

# --- Scontri ----------------------------------------------------------------------

var _scontro: Node3D

## Mette in scena uno scontro: frecce dagli attaccanti al bersaglio, anelli
## colorati e pedine sollevate, così si vede subito chi combatte contro chi.
func mostra_scontro(att: Array, dif: Array, colore_att: Color, colore_dif: Color) -> void:
	pulisci_scontro()
	_scontro = Node3D.new()
	add_child(_scontro)
	var bersaglio := Vector3.ZERO
	for h in dif:
		bersaglio += mondo(h)
	bersaglio /= maxf(1.0, dif.size())
	for h in dif:
		_scontro.add_child(_anello_scontro(h, colore_dif, 1.0))
	for h in att:
		_scontro.add_child(_anello_scontro(h, colore_att, 0.85))
		var freccia := _freccia(mondo(h), bersaglio, colore_att)
		_scontro.add_child(freccia)
	# Le pedine coinvolte si alzano dal tavolo.
	for s in segnalini.values():
		var hex := esagono_da_mondo(s.position)
		if hex in att or hex in dif:
			s.corpo.position.y = 0.06
	for s in citta.values():
		if esagono_da_mondo(s.position) in dif:
			s.corpo.position.y = 0.06

func pulisci_scontro() -> void:
	if _scontro:
		_scontro.queue_free()
		_scontro = null
	for s in segnalini.values():
		s.corpo.position.y = s._sollevato
	for s in citta.values():
		s.corpo.position.y = s._sollevato

func _anello_scontro(h: Vector2i, colore: Color, scala: float) -> MeshInstance3D:
	var a := _anello_esagono(colore, 0.03)
	a.scale = Vector3(scala, 1, scala)
	a.position = mondo(h) + Vector3(0, 0.012, 0)
	var tw := a.create_tween().set_loops()
	tw.tween_property(a.material_override, "albedo_color:a", 0.35, 0.45)
	tw.tween_property(a.material_override, "albedo_color:a", 1.0, 0.45)
	return a

func _freccia(da: Vector3, a: Vector3, colore: Color) -> MeshInstance3D:
	var dir := a - da
	dir.y = 0
	var l := dir.length()
	var asse := dir.normalized()
	var lato := Vector3(-asse.z, 0, asse.x)
	var inizio := da + asse * 0.06
	var fine := a - asse * 0.09
	var largo := 0.032
	var punta := 0.11
	var collo := fine - asse * punta
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := 0.09
	var pts := [
		inizio + lato * largo, collo + lato * largo, collo - lato * largo,
		inizio + lato * largo, collo - lato * largo, inizio - lato * largo,
		collo + lato * largo * 2.6, fine, collo - lato * largo * 2.6,
	]
	for p in pts:
		st.add_vertex(p + Vector3(0, q, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colore
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Sposta una singola pedina (per mostrare passo passo movimenti e ritirate).
func sposta(id: int, h: Vector2i, durata := 0.3) -> void:
	if segnalini.has(id):
		var p := mondo(h)
		segnalini[id].vai_a(Vector3(p.x, segnalini[id].position.y, p.z), durata)

func elimina(id: int) -> void:
	if segnalini.has(id):
		segnalini[id].elimina_animato()
		segnalini.erase(id)
