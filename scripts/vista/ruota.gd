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

var disco: Texture2D = preload("res://assets/ui/ruota_disco.png")
var coperchio: Texture2D = preload("res://assets/ui/ruota_coperchio.png")
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
	if fascia_evidenziata >= 0:
		var r0 := _px(R_FASCE + SP_FASCIA * fascia_evidenziata)
		var r1 := _px(R_FASCE + SP_FASCIA * (fascia_evidenziata + 1))
		var alfa := 0.35 + 0.25 * sin(lampeggio * 7.0)
		_settore(c, r0, r1, -98.0, -82.0, Color(1.0, 0.82, 0.2, alfa))
	# Cartoncino del calendario con la finestra a T.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scala)
	draw_texture(coperchio, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if fascia_evidenziata >= 0:
		var r0 := _px(R_FASCE + SP_FASCIA * fascia_evidenziata)
		var r1 := _px(R_FASCE + SP_FASCIA * (fascia_evidenziata + 1))
		_contorno(c, r0, r1, -99.0, -64.0, Color(1.0, 0.78, 0.1, 0.95), 3.0)

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
	return -90.0 - CENTRI[clampi(dado, 1, 6) - 1]

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
