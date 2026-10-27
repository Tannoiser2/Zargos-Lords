class_name ZRuota
extends Control
## La ruota dei combattimenti originale: il disco fotografato gira sotto il
## cartoncino del calendario e si ferma sul settore del dado; la fascia della
## differenza viene evidenziata nella finestra a T.
##
## Le texture sono generate da tools/genera_ruota.py; le misure qui sotto sono
## in pixel della fotografia del disco (raggio di lavoro 1560 px).

signal finita

const R_LAVORO := 1560.0
const LATO_TEX := 1024.0
## Angolo (gradi, 0 = destra, positivo in senso orario) del centro dei settori
## dei dadi 1-6 nella fotografia del disco.
const CENTRI := [-64.1, -38.5, -13.25, 12.75, 39.6, 66.1]
## Raggio interno della prima fascia (-5/-2) e spessore di ciascuna fascia.
const R_FASCE := 336.0
const SP_FASCIA := 120.5

## Le quattro tabelle delle due ruote originali. Ruota dei combattimenti:
## combattimento (metà destra) e visioni (metà sinistra). Ruota dei tiri:
## fiamme (metà superiore) e frecce (metà inferiore). Per ogni tabella: angoli
## dei settori dei dadi 1-6, raggio della prima fascia, spessore delle fasce e
## arco del contorno attorno alla colonna dei numeri sul cartoncino.
const TABELLE := {
	"combattimento": {"disco": "ruota_disco", "coperchio": "ruota_coperchio", "centri": [-64.55, -38.95, -13.55, 12.45, 39.7, 66.45], "r0": 336.0, "sp": 120.5, "contorno": [-99.0, -64.0]},
	"visione": {"disco": "ruota_disco", "coperchio": "ruota_coperchio", "centri": [115.5, 141.8, 167.75, 193.65, 220.35, 246.9], "r0": 336.0, "sp": 192.8, "contorno": [-114.0, -81.0]},
	"fiamme": {"disco": "ruota_tiri_disco", "coperchio": "ruota_tiri_coperchio", "centri": [-166.0, -138.6, -112.7, -85.6, -57.8, -32.3], "r0": 308.0, "sp": 193.0, "contorno": [-99.0, -71.0]},
	"frecce": {"disco": "ruota_tiri_disco", "coperchio": "ruota_tiri_coperchio", "centri": [18.75, 42.5, 67.5, 92.0, 116.0, 141.0], "r0": 338.0, "sp": 119.0, "contorno": [-110.0, -82.0]},
}
var tabella := "combattimento"

var disco: Texture2D = preload("res://assets/ui/ruota_disco.png")
var coperchio: Texture2D = preload("res://assets/ui/ruota_coperchio.png")

func usa(t: String) -> void:
	tabella = t if TABELLE.has(t) else "combattimento"
	var d: Dictionary = TABELLE[tabella]
	disco = load("res://assets/ui/%s.png" % d.disco)
	coperchio = load("res://assets/ui/%s.png" % d.coperchio)
	queue_redraw()
var scala := 0.62                # texture → schermo
var rotazione := 0.0             # gradi, applicati al disco
var fascia_evidenziata := -1
var lampeggio := 0.0
var _tween: Tween

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_ridimensiona()

func _ridimensiona() -> void:
	# Si vede la metà superiore della ruota, fino al rivetto.
	custom_minimum_size = Vector2(LATO_TEX * scala, LATO_TEX * 0.53 * scala)
	size = custom_minimum_size

func _px(r: float) -> float:
	return r * LATO_TEX / (2.0 * R_LAVORO) * scala

func _centro() -> Vector2:
	return Vector2(LATO_TEX * 0.5, LATO_TEX * 0.5) * scala

func _draw() -> void:
	var c := _centro()
	# Disco girevole.
	draw_set_transform(c, deg_to_rad(rotazione), Vector2.ONE * scala)
	draw_texture(disco, -Vector2(LATO_TEX, LATO_TEX) * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Fascia del risultato, vista attraverso la finestra.
	var tb: Dictionary = TABELLE[tabella]
	if fascia_evidenziata >= 0:
		var r0 := _px(tb.r0 + tb.sp * fascia_evidenziata)
		var r1 := _px(tb.r0 + tb.sp * (fascia_evidenziata + 1))
		var alfa := 0.35 + 0.25 * sin(lampeggio * 7.0)
		_settore(c, r0, r1, -98.0, -82.0, Color(1.0, 0.82, 0.2, alfa))
	# Cartoncino del calendario con la finestra a T.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scala)
	draw_texture(coperchio, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if fascia_evidenziata >= 0:
		var r0 := _px(tb.r0 + tb.sp * fascia_evidenziata)
		var r1 := _px(tb.r0 + tb.sp * (fascia_evidenziata + 1))
		_contorno(c, r0, r1, tb.contorno[0], tb.contorno[1], Color(1.0, 0.78, 0.1, 0.95), 3.0)

func _settore(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := deg_to_rad(lerpf(a0, a1, i / 12.0))
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in 13:
		var a := deg_to_rad(lerpf(a1, a0, i / 12.0))
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	draw_colored_polygon(pts, col)

func _contorno(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var a := deg_to_rad(lerpf(a0, a1, i / 16.0))
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in 17:
		var a := deg_to_rad(lerpf(a1, a0, i / 16.0))
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.6), w + 2.5, true)
	draw_polyline(pts, col, w, true)

func _process(delta: float) -> void:
	if fascia_evidenziata >= 0:
		lampeggio += delta
		queue_redraw()

func angolo_per_dado(dado: int) -> float:
	return -90.0 - float(TABELLE[tabella].centri[clampi(dado, 1, 6) - 1])

func _imposta_rotazione(v: float) -> void:
	rotazione = v
	queue_redraw()

## Fa girare il disco fino al dado indicato ed evidenzia la fascia.
## `durata` è il tempo del giro; la ruota decelera come spinta a mano.
func gira(dado: int, fascia: int, durata := 1.6) -> void:
	fascia_evidenziata = -1
	var arrivo := angolo_per_dado(dado)
	var partenza := arrivo - 360.0 * 2.0 - randf_range(40.0, 140.0)
	rotazione = partenza
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_imposta_rotazione, partenza, arrivo, durata).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func():
		fascia_evidenziata = fascia
		lampeggio = 0.0
		finita.emit())
