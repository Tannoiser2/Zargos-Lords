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
	# Bordi degli esagoni come nastri sottili neri (le linee GL hanno sempre 1 pixel).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := mappa.raggio_px / SCALA
	var mezzo := r * 0.035
	for riga in mappa.righe:
		for col in mappa.colonne:
			var h := Vector2i(col, riga)
			if not mappa.terra(h):
				continue
			var c := mondo(h) + Vector3(0, 0.004, 0)
			for i in 6:
				var a := deg_to_rad(60.0 * i - 90.0)
				var b := deg_to_rad(60.0 * (i + 1) - 90.0)
				var pa := c + Vector3(cos(a), 0, sin(a)) * r
				var pb := c + Vector3(cos(b), 0, sin(b)) * r
				var lato := (pb - pa).cross(Vector3.UP).normalized() * mezzo
				for v in [pa - lato, pb - lato, pb + lato, pa - lato, pb + lato, pa + lato]:
					st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.05, 0.04, 0.03, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_griglia = MeshInstance3D.new()
	_griglia.mesh = st.commit()
	_griglia.material_override = m
	_griglia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

## Due pezzi nello stesso esagono (pila di Zargo's Lords 2 o fante di scorta)
## si dispongono affiancati e rimpiccioliti dentro l'esagono, così è chiaro che
## occupano lo stesso esagono e non sconfinano nei vicini.
const SCALA_PILA := 0.6
const ALTEZZA_SCORTA_3D := 0.0
func _pila(g: ZPartita, u: ZPedina) -> Array:
	if u.scomparso:
		return [0, 1]
	var pila := g.pedine_in(u.hex).filter(func(w): return w.viva and w.schierata and w.citta < 0 and not w.scomparso)
	pila.sort_custom(func(a, b): return (1 if a.scorta >= 0 else 0) * 100000 + a.id < (1 if b.scorta >= 0 else 0) * 100000 + b.id)
	return [maxi(0, pila.find(u)), pila.size()]

## Pila affiancata (Zargo's Lords 2). La scorta del gioco base invece si
## mostra come sul tavolo: il fante sovrapposto al pezzo che scorta.
func _affiancati(g: ZPartita, u: ZPedina) -> bool:
	return _pila(g, u)[1] >= 2 and u.scorta < 0 and u.scortato_da < 0

func _posizione_pedina(g: ZPartita, u: ZPedina) -> Vector3:
	var p := mondo(u.hex)
	p.y += altezza_terreno(g, u.hex)
	if u.scorta >= 0:
		# Fante di scorta: sopra lo scortato, un po' spostato perché si veda chi c'è sotto.
		p.y += ZSegnalino.SPESSORE + (ALTEZZA_SCORTA_3D if ZTema.grafica == "3d" else 0.0)
		p += Vector3(0.045, 0, 0.045) if ZTema.grafica != "3d" else Vector3(0.07, 0, 0.07)
		return p
	if u.scortato_da >= 0:
		return p
	if _affiancati(g, u):
		var pl := _pila(g, u)
		var lato := -1.0 if pl[0] == 0 else 1.0
		p += Vector3(lato * ZSegnalino.RAGGIO * 0.56, 0, 0)
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
			s.grigio(false)
			s.scale = Vector3.ONE * 0.75
			s.testo("")
		elif u.ridotta:
			# Pezzo ridotto: tutto grigio, come pietrificato.
			s.faccia(u.tipo)
			s.grigio(true)
			s.scale = Vector3.ONE * (SCALA_PILA if _affiancati(g, u) else 1.0)
			s.testo("")
		else:
			s.faccia(u.tipo)
			s.grigio(false)
			s.scale = Vector3.ONE * (SCALA_PILA if _affiancati(g, u) else 1.0)
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
	aggiorna_terreno_3d(g)
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

# --- Terreno in 3D (miniature Meshy nello stile della mappa di Riboldi) -------------

const MODELLI_TERRENO := {
	"montagna": "res://assets/modelli/terreno/montagna.glb",
	"bosco": "res://assets/modelli/terreno/bosco.glb",
	"gorgo": "res://assets/modelli/terreno/gorgo.glb",
	"ponte": "res://assets/modelli/terreno/ponte.glb",
}
## Altezza dei rilievi: i pezzi che vi sostano poggiano sopra.
const ALTEZZA_RILIEVO := {"montagna": 0.15, "bosco": 0.085, "gorgo": 0.035}
var _terreno3d: Node3D
var _chiave_terreno := ""
static var _cache_modelli := {}

func _tipo_rilievo(t: int) -> String:
	match t:
		ZMappa.T.MONTAGNA: return "montagna"
		ZMappa.T.BOSCO: return "bosco"
		ZMappa.T.GORGO: return "gorgo"
	return ""

## Rilievi 3D accesi o spenti (pulsante nella barra in alto).
static var rilievi := true

func altezza_terreno(g: ZPartita, h: Vector2i) -> float:
	if not rilievi or g == null:
		return 0.0
	if not g.citta_in(h).is_empty():
		return 0.0
	return float(ALTEZZA_RILIEVO.get(_tipo_rilievo(g.terreno(h)), 0.0))

## Mesh, materiale e ingombro di un modello del terreno (prima MeshInstance).
func _modello(nome: String) -> Dictionary:
	if _cache_modelli.has(nome):
		return _cache_modelli[nome]
	var d := {}
	var sc: PackedScene = load(MODELLI_TERRENO[nome]) if ResourceLoader.exists(MODELLI_TERRENO[nome]) else null
	if sc:
		var n := sc.instantiate()
		var trovati := n.find_children("*", "MeshInstance3D", true, false)
		if not trovati.is_empty():
			var mi: MeshInstance3D = trovati[0]
			var t := Transform3D.IDENTITY
			var x: Node = mi
			while x != null and x != n:
				if x is Node3D:
					t = (x as Node3D).transform * t
				x = x.get_parent()
			d = {"mesh": mi.mesh, "base": t, "box": t * mi.get_aabb()}
		n.free()
	_cache_modelli[nome] = d
	return d

func _multi(nome: String, trasformazioni: Array) -> void:
	var d := _modello(nome)
	if d.is_empty() or trasformazioni.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = d.mesh
	mm.instance_count = trasformazioni.size()
	for i in trasformazioni.size():
		mm.set_instance_transform(i, trasformazioni[i] * d.base)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_terreno3d.add_child(mmi)

## Montagne, boschi, gorghi e ponti di nuvole in rilievo, solo con la grafica 3D.
## Gli esagoni con una città restano piatti.
func aggiorna_terreno_3d(g: ZPartita) -> void:
	var chiave := ""
	if rilievi and g != null:
		var parti: PackedStringArray = []
		for ci in g.citta:
			parti.append("%d,%d" % [ci.h[0], ci.h[1]])
		parti.append(str(g.terreno_mod.keys()))
		parti.append(str(g.ponti_temp))
		chiave = ";".join(parti)
	if chiave == _chiave_terreno:
		return
	_chiave_terreno = chiave
	if _terreno3d:
		_terreno3d.queue_free()
		_terreno3d = null
	if chiave == "":
		return
	_terreno3d = Node3D.new()
	add_child(_terreno3d)
	var r_hex := mappa.raggio_px / SCALA
	var gruppi := {"montagna": [], "bosco": [], "gorgo": []}
	var caso := RandomNumberGenerator.new()
	for y in mappa.righe:
		for x in mappa.colonne:
			var h := Vector2i(x, y)
			var tipo := _tipo_rilievo(g.terreno(h))
			if tipo == "" or not g.citta_in(h).is_empty():
				continue
			caso.seed = x * 1000 + y
			var d := _modello(tipo)
			if d.is_empty():
				continue
			var box: AABB = d.box
			var alt: float = ALTEZZA_RILIEVO[tipo]
			# Altezza del rilievo e larghezza pari all'esagono; il gorgo resta basso.
			var s_xz := r_hex * 1.75 / maxf(box.size.x, box.size.z)
			var s_y := alt / maxf(box.size.y, 0.001)
			if tipo == "gorgo":
				s_y = s_xz * 0.6
			var base := Basis.from_euler(Vector3(0, caso.randf() * TAU if tipo != "montagna" else deg_to_rad(60.0 * caso.randi_range(0, 5)), 0)) * Basis.from_scale(Vector3(s_xz, s_y, s_xz))
			var centro := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
			var t := Transform3D(base, mondo(h) - base * centro)
			gruppi[tipo].append(t)
	for k in gruppi:
		_multi(k, gruppi[k])
	# Ponti di nuvole, fissi e temporanei (Ponte di pensiero).
	var ponti := []
	for c in mappa.coppie_ponti():
		ponti.append(c)
	for pt in g.ponti_temp:
		ponti.append([Vector2i(int(pt[0][0]), int(pt[0][1])), Vector2i(int(pt[1][0]), int(pt[1][1]))])
	var tp := []
	var dp := _modello("ponte")
	if not dp.is_empty():
		var box: AABB = dp.box
		var lungo := box.size.x >= box.size.z
		for c in ponti:
			var a := mondo(c[0])
			var b := mondo(c[1])
			var v := b - a
			var l := v.length()
			var s_l := l * 0.95 / (box.size.x if lungo else box.size.z)
			var s_w := r_hex * 0.7 / (box.size.z if lungo else box.size.x)
			var ang := atan2(-v.z, v.x) if lungo else atan2(v.x, v.z)
			var sc := Vector3(s_l, s_l * 0.5, s_w) if lungo else Vector3(s_w, s_l * 0.5, s_l)
			var base := Basis(Vector3.UP, ang) * Basis.from_scale(sc)
			var centro := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
			tp.append(Transform3D(base, (a + b) * 0.5 - base * centro))
	_multi("ponte", tp)

func segnalino(id: int) -> ZSegnalino:
	return segnalini.get(id)

func seleziona_pedine(ids: Array, colore := ZTema.OCRA) -> void:
	for id in segnalini:
		segnalini[id].seleziona(id in ids, colore)

# --- Effetti ----------------------------------------------------------------------

## Proiettile (freccia, vampa o visione) che vola da un esagono all'altro.
## Animazione dei lanci. Il tiratore si gira verso il bersaglio e si carica,
## poi partono frecce (a raffica, in arco), fiamme (sciame di braci) o visioni
## (anelli spettrali); all'arrivo il bersaglio sussulta. Dura circa 1,2 s.
func lancia(da: Vector2i, a: Vector2i, tipo: String, id_tiratore := -1, id_bersaglio := -1) -> void:
	var o := mondo(da)
	var f := mondo(a)
	var st: ZSegnalino = segnalini.get(id_tiratore)
	var sb: ZSegnalino = segnalini.get(id_bersaglio)
	if st:
		o = st.position
	if sb:
		f = sb.position
	var altezza_partenza := 0.2 if ZTema.grafica == "3d" else 0.08
	if st:
		await st.carica_tiro(f)
	match tipo:
		"frecce", "cavallo", "dardi":
			var colore := Color("8fbf5a") if tipo == "dardi" else Color("e9dcc0")
			for k in 3:
				var sp := Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
				_freccia_volante(o + Vector3(0, altezza_partenza, 0), f + sp + Vector3(0, 0.05, 0), colore, 0.5)
				await get_tree().create_timer(0.09).timeout
			await get_tree().create_timer(0.45).timeout
		"fiamme":
			for k in 26:
				_brace(o + Vector3(0, altezza_partenza * 0.9, 0), f + Vector3(0, 0.05, 0))
				await get_tree().create_timer(0.025).timeout
			await get_tree().create_timer(0.35).timeout
			_esplosione(f, Color(1.0, 0.5, 0.1), Color(0.9, 0.15, 0.05))
		_:
			for k in 3:
				_anello_visione(o + Vector3(0, altezza_partenza, 0), f + Vector3(0, 0.1, 0))
				await get_tree().create_timer(0.12).timeout
			await get_tree().create_timer(0.45).timeout
			_esplosione(f, Color(0.8, 0.6, 1.0), Color(0.35, 0.15, 0.7))
	if sb:
		sb.sussulta()

func _materiale_luce(colore: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colore
	return m

func _freccia_volante(o: Vector3, f: Vector3, colore: Color, durata: float) -> void:
	var freccia := Node3D.new()
	var asta := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0035
	c.bottom_radius = 0.0035
	c.height = 0.11
	c.radial_segments = 6
	asta.mesh = c
	asta.material_override = _materiale_luce(colore)
	asta.rotation.x = PI / 2
	freccia.add_child(asta)
	var punta := MeshInstance3D.new()
	var cp := CylinderMesh.new()
	cp.top_radius = 0.0
	cp.bottom_radius = 0.009
	cp.height = 0.025
	cp.radial_segments = 6
	punta.mesh = cp
	punta.material_override = _materiale_luce(Color(0.55, 0.6, 0.65))
	punta.rotation.x = -PI / 2
	punta.position.z = -0.065
	freccia.add_child(punta)
	var coda := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.012
	cc.bottom_radius = 0.0
	cc.height = 0.025
	cc.radial_segments = 3
	coda.mesh = cc
	coda.material_override = _materiale_luce(Color(0.75, 0.2, 0.15))
	coda.rotation.x = -PI / 2
	coda.position.z = 0.05
	freccia.add_child(coda)
	freccia.scale = Vector3.ONE * 1.7
	effetti.add_child(freccia)
	var alt := o.distance_to(f) * 0.3
	var pos := func(t: float) -> Vector3:
		var q := o.lerp(f, t)
		q.y += sin(t * PI) * alt
		return q
	freccia.position = o
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var q: Vector3 = pos.call(t)
		var avanti: Vector3 = pos.call(minf(1.0, t + 0.02))
		freccia.position = q
		if avanti.distance_to(q) > 0.0001:
			freccia.look_at(avanti, Vector3.UP)
			freccia.scale = Vector3.ONE * 1.7
	, 0.0, 1.0, durata)
	tw.tween_interval(0.25)
	tw.tween_callback(freccia.queue_free)

func _brace(o: Vector3, f: Vector3) -> void:
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.02
	sm.height = 0.04
	sm.radial_segments = 8
	sm.rings = 4
	b.mesh = sm
	var m := _materiale_luce(Color(1.0, 0.85, 0.3, 0.95))
	b.material_override = m
	effetti.add_child(b)
	b.position = o
	var jitter := Vector3(randf_range(-0.04, 0.04), randf_range(-0.02, 0.05), randf_range(-0.04, 0.04))
	var alt := o.distance_to(f) * 0.12
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var q := o.lerp(f + jitter, t)
		q.y += sin(t * PI) * alt
		b.position = q
		b.scale = Vector3.ONE * (0.6 + t * 1.6)
		m.albedo_color = Color(1.0, 0.85, 0.3).lerp(Color(0.9, 0.2, 0.05), t)
		m.albedo_color.a = 0.95 - t * 0.35
	, 0.0, 1.0, 0.4)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(b.queue_free)

func _anello_visione(o: Vector3, f: Vector3) -> void:
	var a := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.035
	t.outer_radius = 0.05
	a.mesh = t
	var m := _materiale_luce(Color(0.78, 0.6, 1.0, 0.85))
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	a.material_override = m
	effetti.add_child(a)
	a.position = o
	var tw := create_tween()
	tw.tween_method(func(x: float):
		var q := o.lerp(f, x)
		q.y += sin(x * PI) * 0.08 + sin(x * PI * 4.0) * 0.015
		a.position = q
		a.rotation = Vector3(x * PI * 3.0, x * PI * 2.0, 0)
		a.scale = Vector3.ONE * (0.7 + sin(x * PI) * 0.6)
	, 0.0, 1.0, 0.55)
	tw.tween_property(a, "scale", Vector3.ONE * 2.5, 0.2)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(a.queue_free)

## Lampo di particelle (fiamme, visioni, fumo).
func _esplosione(h: Vector3, c1: Color, c2: Color, n := 24, su := 0.25, durata := 0.6, grandezza := 1.0) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	p.amount = n
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = durata
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = su * 0.5
	p.initial_velocity_max = su
	p.gravity = Vector3(0, 0.1, 0)
	p.scale_amount_min = 1.0 * grandezza
	p.scale_amount_max = 2.5 * grandezza
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, Color(c2, 0.0))
	p.color_ramp = g
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.6))
	curva.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curva
	p.position = h + Vector3(0, 0.05, 0)
	effetti.add_child(p)
	p.emitting = true
	get_tree().create_timer(durata + 0.3).timeout.connect(p.queue_free)

## Il Signore Monaco svanisce in una nuvola di fumo dorato.
func svanisci(id: int) -> void:
	var s: ZSegnalino = segnalini.get(id)
	if s == null:
		return
	_esplosione(s.position, Color(1.0, 0.97, 0.85, 1.0), Color(0.95, 0.75, 0.35), 50, 0.2, 1.3, 2.6)
	_esplosione(s.position, Color(1.0, 0.8, 0.3, 1.0), Color(1.0, 0.5, 0.1), 16, 0.35, 0.6, 1.2)
	var tw := s.create_tween()
	tw.tween_property(s, "position:y", s.position.y + 0.12, 0.6).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(s, "scale", Vector3.ONE * 0.05, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tw.finished

## Ricomparsa: fumo dorato e il pezzo che cresce dal nulla.
func ricompari(id: int, h: Vector2i) -> void:
	var p := mondo(h)
	_esplosione(p, Color(1.0, 0.97, 0.85, 1.0), Color(0.95, 0.75, 0.35), 50, 0.2, 1.3, 2.6)
	var s: ZSegnalino = segnalini.get(id)
	if s == null:
		return
	s.position = p
	s.faccia(s.tipo)
	s.scale = Vector3.ONE * 0.05
	var tw := s.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(s, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

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
		_scontro.add_child(_freccia_arco(mondo(h), bersaglio, colore_att))
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

## Freccia d'attacco: un arco che scavalca le pedine e scende sul bersaglio
## con una punta ben marcata, nel colore del popolo che attacca e bordata di scuro.
func _freccia_arco(da: Vector3, a: Vector3, colore: Color) -> Node3D:
	var n := Node3D.new()
	var quota := 0.32 if ZTema.grafica == "3d" else 0.1
	var dir := a - da
	dir.y = 0
	var asse := dir.normalized()
	var p0 := da + asse * 0.03 + Vector3(0, quota, 0)
	var p2 := a - asse * 0.02 + Vector3(0, quota * 0.55 + 0.03, 0)
	var p1 := (p0 + p2) * 0.5 + Vector3(0, 0.12 + dir.length() * 0.25, 0)
	var curva := func(t: float) -> Vector3:
		return p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
	n.add_child(_tubo(curva, 0.016, 0.07, Color(0.08, 0.05, 0.03), 1))
	n.add_child(_tubo(curva, 0.011, 0.06, colore, 2))
	return n

## Tubo lungo una curva, che termina con una punta conica (lunghezza `punta`).
func _tubo(curva: Callable, raggio: float, punta: float, colore: Color, priorita: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var passi := 24
	var lati := 8
	var pts: Array[Vector3] = []
	for i in passi + 1:
		pts.append(curva.call(i / float(passi)))
	# Lunghezza totale per sapere dove inizia la punta.
	var cum: Array[float] = [0.0]
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var tot: float = cum[cum.size() - 1]
	var inizio_punta := maxf(0.0, tot - punta)
	var anelli: Array = []
	for i in pts.size():
		var t := pts[i]
		var tang := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var su := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var x := tang.cross(su).normalized()
		var y := x.cross(tang).normalized()
		var r := raggio
		if cum[i] >= inizio_punta:
			r = raggio * 3.2 * (tot - cum[i]) / maxf(punta, 0.001)
		var anello: Array[Vector3] = []
		for k in lati:
			var ang := TAU * k / lati
			anello.append(t + (x * cos(ang) + y * sin(ang)) * r)
		anelli.append(anello)
		# Gradino alla base della punta.
		if i + 1 < pts.size() and cum[i] < inizio_punta and cum[i + 1] >= inizio_punta:
			var base: Array[Vector3] = []
			var tb := t.lerp(pts[i + 1], (inizio_punta - cum[i]) / maxf(cum[i + 1] - cum[i], 0.0001))
			for k in lati:
				var ang := TAU * k / lati
				base.append(tb + (x * cos(ang) + y * sin(ang)) * raggio)
			anelli.append(base)
			var larga: Array[Vector3] = []
			for k in lati:
				var ang := TAU * k / lati
				larga.append(tb + (x * cos(ang) + y * sin(ang)) * raggio * 3.2)
			anelli.append(larga)
	for i in anelli.size() - 1:
		var a1: Array = anelli[i]
		var a2: Array = anelli[i + 1]
		for k in lati:
			var k2 := (k + 1) % lati
			for v in [a1[k], a2[k], a2[k2], a1[k], a2[k2], a1[k2]]:
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colore
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = priorita
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

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
