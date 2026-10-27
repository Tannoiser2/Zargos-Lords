class_name ZTema
extends RefCounted
## Stile grafico ispirato ai materiali originali International Team (1979):
## ruote in cartone color cuoio con settori avorio e grigi, titoli in un
## bastone condensato pesante come il logo della scatola, testi in un
## geometrico alla Futura come quello delle ruote.

const CUOIO := Color("5b3422")
const CUOIO_SCURO := Color("2e1a11")
const CUOIO_CHIARO := Color("7a4a31")
const AVORIO := Color("ece4d0")
const CARTA := Color("ddd3ba")
const GRIGIO := Color("b8b2a6")
const INCHIOSTRO := Color("1f1611")
const TERRA_ROSA := Color("cf8a6c")
const OCRA := Color("d9a441")
const ROSSO := Color("b8412f")
const VERDE := Color("6f8f37")

static var titolo: Font = load("res://assets/fonts/Anton-Regular.ttf")
static var testo: Font = _jost(420)
static var testo_forte: Font = _jost(600)

static func _jost(peso: int) -> Font:
	var base: FontFile = load("res://assets/fonts/Jost.ttf")
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): peso}
	return v

static func riquadro(fondo: Color, bordo: Color = CUOIO_SCURO, spessore := 2, raggio := 6, margine := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = bordo
	s.set_border_width_all(spessore)
	s.set_corner_radius_all(raggio)
	s.content_margin_left = margine
	s.content_margin_right = margine
	s.content_margin_top = margine * 0.7
	s.content_margin_bottom = margine * 0.7
	s.anti_aliasing = true
	return s

static func crea() -> Theme:
	var t := Theme.new()
	t.default_font = testo
	t.default_font_size = 16
	t.set_color("font_color", "Label", INCHIOSTRO)
	t.set_color("default_color", "RichTextLabel", INCHIOSTRO)
	t.set_font("bold_font", "RichTextLabel", testo_forte)
	t.set_font("normal_font", "RichTextLabel", testo)
	# Pulsanti: cartoncino avorio con bordo cuoio, premuti diventano cuoio.
	var normale := riquadro(AVORIO, CUOIO, 2, 4, 12)
	var sopra := riquadro(Color("fff6e0"), CUOIO_SCURO, 2, 4, 12)
	var premuto := riquadro(CUOIO, CUOIO_SCURO, 2, 4, 12)
	var spento := riquadro(Color(0.85, 0.82, 0.75, 0.6), Color(0.45, 0.35, 0.28, 0.5), 2, 4, 12)
	for tipo in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", tipo, normale)
		t.set_stylebox("hover", tipo, sopra)
		t.set_stylebox("pressed", tipo, premuto)
		t.set_stylebox("hover_pressed", tipo, premuto)
		t.set_stylebox("disabled", tipo, spento)
		t.set_stylebox("focus", tipo, StyleBoxEmpty.new())
		t.set_color("font_color", tipo, INCHIOSTRO)
		t.set_color("font_hover_color", tipo, INCHIOSTRO)
		t.set_color("font_pressed_color", tipo, AVORIO)
		t.set_color("font_hover_pressed_color", tipo, AVORIO)
		t.set_color("font_disabled_color", tipo, Color(0.3, 0.25, 0.2, 0.6))
		t.set_font("font", tipo, testo_forte)
	t.set_stylebox("panel", "PanelContainer", riquadro(AVORIO, CUOIO_SCURO, 3, 8, 14))
	t.set_stylebox("panel", "Panel", riquadro(AVORIO, CUOIO_SCURO, 3, 8, 14))
	t.set_stylebox("panel", "PopupMenu", riquadro(AVORIO, CUOIO_SCURO, 2, 4, 8))
	t.set_color("font_color", "PopupMenu", INCHIOSTRO)
	t.set_color("font_hover_color", "PopupMenu", AVORIO)
	t.set_stylebox("hover", "PopupMenu", riquadro(CUOIO, CUOIO, 0, 2, 4))
	t.set_font("font", "PopupMenu", testo_forte)
	t.set_stylebox("normal", "LineEdit", riquadro(Color("f7f1e2"), CUOIO, 2, 4, 8))
	t.set_stylebox("focus", "LineEdit", riquadro(Color("fffaf0"), OCRA, 2, 4, 8))
	t.set_color("font_color", "LineEdit", INCHIOSTRO)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.3, 0.25, 0.2, 0.5))
	t.set_color("caret_color", "LineEdit", CUOIO)
	t.set_stylebox("scroll", "VScrollBar", riquadro(Color(0, 0, 0, 0.06), Color(0, 0, 0, 0), 0, 3, 3))
	t.set_stylebox("grabber", "VScrollBar", riquadro(CUOIO_CHIARO, CUOIO_CHIARO, 0, 3, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", riquadro(CUOIO, CUOIO, 0, 3, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", riquadro(CUOIO_SCURO, CUOIO_SCURO, 0, 3, 3))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_stylebox("separator", "HSeparator", _linea())
	t.set_color("font_color", "CheckBox", INCHIOSTRO)
	t.set_stylebox("panel", "TooltipPanel", riquadro(INCHIOSTRO, OCRA, 1, 3, 8))
	t.set_color("font_color", "TooltipLabel", AVORIO)
	t.set_font("font", "TooltipLabel", testo)
	return t

static func _linea() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(CUOIO, 0.45)
	l.thickness = 2
	return l

static func etichetta(testo_: String, dimensione := 16, colore := INCHIOSTRO, font: Font = null) -> Label:
	var l := Label.new()
	l.text = testo_
	l.add_theme_font_size_override("font_size", dimensione)
	l.add_theme_color_override("font_color", colore)
	if font != null:
		l.add_theme_font_override("font", font)
	return l

static func titoletto(testo_: String, dimensione := 22, colore := CUOIO) -> Label:
	var l := etichetta(testo_.to_upper(), dimensione, colore, titolo)
	return l

static func pulsante(testo_: String, azione: Callable = Callable(), dimensione := 16) -> Button:
	var b := Button.new()
	b.text = testo_
	b.add_theme_font_size_override("font_size", dimensione)
	b.focus_mode = Control.FOCUS_NONE
	if azione.is_valid():
		b.pressed.connect(azione)
	return b

## Pulsante principale in colore cuoio, come il centro delle ruote.
static func pulsante_forte(testo_: String, azione: Callable = Callable(), dimensione := 20) -> Button:
	var b := pulsante(testo_, azione, dimensione)
	b.add_theme_font_override("font", titolo)
	b.add_theme_stylebox_override("normal", riquadro(CUOIO, CUOIO_SCURO, 3, 4, 16))
	b.add_theme_stylebox_override("hover", riquadro(CUOIO_CHIARO, CUOIO_SCURO, 3, 4, 16))
	b.add_theme_stylebox_override("pressed", riquadro(CUOIO_SCURO, INCHIOSTRO, 3, 4, 16))
	b.add_theme_color_override("font_color", AVORIO)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b

## Grafica delle pedine: "originale" (scansioni 1979), "nuova" o "3d"
## (nuove facce più le miniature generate con Meshy).
static var grafica := "nuova"

static func percorso_pedina(popolo: String, tipo: String) -> String:
	var orig := "res://assets/units/%s/%s.png" % [popolo.to_lower(), tipo]
	if grafica != "originale":
		var t := "pantera" if tipo == "pantera0" else tipo
		var nuovo := "res://assets/units_nuove/%s/%s.png" % [popolo.to_lower(), t]
		if ResourceLoader.exists(nuovo):
			return nuovo
	return orig

static func texture_pedina(popolo: String, tipo: String) -> Texture2D:
	return load(percorso_pedina(popolo, tipo))

## Disegno del Signore per il menu, coerente con la grafica scelta.
static func ritratto_signore(popolo: String) -> Texture2D:
	var p := popolo.to_lower()
	var cartelle := {"originale": ["signori"], "nuova": ["signori_nuovi", "signori"], "3d": ["signori_3d", "signori_nuovi", "signori"]}
	for c in cartelle.get(grafica, ["signori"]):
		var f := "res://assets/ui/%s/%s.png" % [c, p]
		if ResourceLoader.exists(f):
			return load(f)
	return null

## Miniatura 3D del pezzo, se esiste.
static func percorso_modello(popolo: String, tipo: String) -> String:
	var mappa_tipi := {"pantera0": "pantera", "megadrago": "signore"}
	var pp := "draghi" if tipo == "megadrago" else popolo.to_lower()
	var f := "res://assets/modelli/%s/%s.glb" % [pp, mappa_tipi.get(tipo, tipo)]
	return f if ResourceLoader.exists(f) else ""
