class_name ZWidget
extends RefCounted
## Piccoli elementi disegnati a mano: calendario, dado, spicchio della ruota.

## Il calendario dei 25 mesi, come sulla ruota: i mesi trascorsi sono barrati.
class Calendario extends Control:
	const PASSO := 23.5
	var mese := 1
	func _init() -> void:
		custom_minimum_size = Vector2(25 * PASSO + 8, 32)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func imposta(m: int) -> void:
		mese = m
		queue_redraw()
	func _draw() -> void:
		var font := ZTema.testo_forte
		for i in 25:
			var c := Vector2(14 + i * PASSO, size.y * 0.5)
			var n := i + 1
			var attuale := n == mese
			if attuale:
				draw_circle(c, 11.5, ZTema.AVORIO)
				draw_arc(c, 11.5, 0, TAU, 28, ZTema.OCRA, 2.2, true)
			else:
				draw_arc(c, 10.5, 0, TAU, 28, Color(ZTema.AVORIO, 0.75 if n > mese else 0.35), 1.5, true)
			var s := str(n)
			var dim := 12
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, dim).x
			var col := ZTema.INCHIOSTRO if attuale else Color(ZTema.AVORIO, 0.9 if n > mese else 0.4)
			draw_string(font, c + Vector2(-w * 0.5, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, dim, col)
			if n < mese:
				# Tratto di penna, un po' storto come sull'originale.
				var o := Vector2(sin(i * 1.7) * 1.5, cos(i * 2.3) * 1.5)
				draw_line(c + Vector2(-9, 8) + o, c + Vector2(9, -8) - o, Color("e6dcc4"), 2.0, true)

## Faccia di un dado a sei.
class Dado extends Control:
	var valore := 1
	var colore := ZTema.AVORIO
	func _init(dim := 64.0) -> void:
		custom_minimum_size = Vector2(dim, dim)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func imposta(v: int) -> void:
		valore = v
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-2)
		var sb := ZTema.riquadro(colore, ZTema.INCHIOSTRO, 2, int(size.x * 0.16), 0)
		draw_style_box(sb, r)
		var punti := {
			1: [Vector2(0.5, 0.5)],
			2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
			3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
			4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
			5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
			6: [Vector2(0.27, 0.25), Vector2(0.73, 0.25), Vector2(0.27, 0.5), Vector2(0.73, 0.5), Vector2(0.27, 0.75), Vector2(0.73, 0.75)],
		}
		for p in punti.get(valore, []):
			draw_circle(r.position + p * r.size, size.x * 0.085, ZTema.INCHIOSTRO)

## Lo spicchio della ruota dei combattimenti per una certa differenza: per
## ciascuna faccia del dado mostra l'esito, colorato a favore di chi vince.
class Spicchio extends Control:
	var esiti: Array = []
	var evidenziato := 0
	func _init() -> void:
		custom_minimum_size = Vector2(240, 52)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func imposta(differenza: int, dado := 0) -> void:
		esiti.clear()
		for d in range(1, 7):
			esiti.append(ZRegole.esito_combattimento(differenza, d))
		evidenziato = dado
		queue_redraw()
	func _draw() -> void:
		var w := size.x / 6.0
		var font := ZTema.titolo
		for i in 6:
			var r := Rect2(i * w + 1, 0, w - 2, size.y)
			var e: String = esiti[i] if i < esiti.size() else ""
			var col := ZTema.GRIGIO
			if e.begins_with("D"):
				col = Color("8fae5c") if e == "DE" else Color("c3cf98")
			elif e.begins_with("A"):
				col = Color("c35a43") if e == "AE" else Color("e2a28d")
			var sb := ZTema.riquadro(col, ZTema.CUOIO_SCURO if evidenziato != i + 1 else ZTema.OCRA, 2 if evidenziato != i + 1 else 4, 4, 0)
			draw_style_box(sb, r)
			var testo := str(i + 1)
			draw_string(ZTema.testo_forte, r.position + Vector2(5, 13), testo, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ZTema.INCHIOSTRO, 0.6))
			var dim := 22
			var tw := font.get_string_size(e, HORIZONTAL_ALIGNMENT_CENTER, -1, dim).x
			draw_string(font, r.position + Vector2((r.size.x - tw) * 0.5, size.y - 11), e, HORIZONTAL_ALIGNMENT_LEFT, -1, dim, ZTema.INCHIOSTRO)

## Barretta di colore del popolo.
class Gettone extends Control:
	var colore := Color.WHITE
	func _init(c: Color, dim := 14.0) -> void:
		colore = c
		custom_minimum_size = Vector2(dim, dim)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := size.x * 0.5
		var pts := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * i - 90.0)
			pts.append(Vector2(r, r) + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, colore)
		pts.append(pts[0])
		draw_polyline(pts, ZTema.INCHIOSTRO, 1.5, true)

## Pulsante con un'icona disegnata (i font web non hanno i simboli).
class Icona extends Button:
	var tipo := ""
	func _init(t: String, suggerimento: String, azione: Callable) -> void:
		tipo = t
		tooltip_text = suggerimento
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(38, 34)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pressed.connect(azione)
	func _draw() -> void:
		var c := size * 0.5
		var col := ZTema.INCHIOSTRO
		var w := 2.2
		match tipo:
			"sx", "dx":
				var verso := -1.0 if tipo == "sx" else 1.0
				var pts := PackedVector2Array()
				for i in 19:
					var ang := deg_to_rad(-40.0 + i * 15.0)
					pts.append(c + Vector2(cos(ang) * verso, sin(ang)) * 8.5)
				draw_polyline(pts, col, w, true)
				var fine := pts[pts.size() - 1]
				var tang := (fine - pts[pts.size() - 2]).normalized()
				var norm := Vector2(-tang.y, tang.x)
				draw_colored_polygon(PackedVector2Array([fine + tang * 4.5, fine - tang * 1.5 + norm * 4.0, fine - tang * 1.5 - norm * 4.0]), col)
			"griglia":
				var pts := PackedVector2Array()
				for i in 7:
					var a := deg_to_rad(60.0 * i - 90.0)
					pts.append(c + Vector2(cos(a), sin(a)) * 9.5)
				draw_polyline(pts, col, w, true)
			"aiuto":
				draw_string(ZTema.titolo, c + Vector2(-5, 8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
			"casa":
				var pts := PackedVector2Array([c + Vector2(-9, 0), c + Vector2(0, -9), c + Vector2(9, 0)])
				draw_polyline(pts, col, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-6, -2), c + Vector2(-6, 8), c + Vector2(6, 8), c + Vector2(6, -2)]), col, w, true)
				draw_rect(Rect2(c + Vector2(-2, 2), Vector2(4, 6)), col)
			"menu":
				for dy in [-6, 0, 6]:
					draw_line(c + Vector2(-9, dy), c + Vector2(9, dy), col, w, true)
