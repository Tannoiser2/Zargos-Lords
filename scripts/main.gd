extends Node3D

const BOARD_SIZE := Vector2(16.0, 10.738)
const HEX_RADIUS := 0.42

var state := ZargosGameState.new()
var board_data := ZargosBoardData.new()
var camera: Camera3D
var camera_rig: Node3D
var camera_pitch: Node3D
var selected: CardboardUnit
var status_label: Label
var details_label: Label
var score_label: Label
var event_label: Label
var grid_overlay: MeshInstance3D
var rng := RandomNumberGenerator.new()
var orbiting := false
var panning := false
var orbit_yaw := 0.0
var orbit_pitch := -0.82
var camera_distance := 12.8

func _ready() -> void:
	rng.randomize()
	_build_environment()
	_build_board()
	_build_hex_overlay()
	_build_camera()
	_build_lights()
	_build_ui()
	_spawn_demo_armies()
	_spawn_cities()
	state.state_changed.connect(_refresh_ui)
	state.log_message.connect(_show_event)
	_refresh_ui()

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("160f0b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e1b879")
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

func _build_board() -> void:
	var board := StaticBody3D.new()
	board.name = "Board"
	board.set_meta("is_board", true)
	add_child(board)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BOARD_SIZE.x, 0.22, BOARD_SIZE.y)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/board/zargo_board.png")
	material.roughness = 0.78
	box.material = material
	mesh_instance.mesh = box
	board.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BOARD_SIZE.x, 0.24, BOARD_SIZE.y)
	collision.shape = shape
	board.add_child(collision)

	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(BOARD_SIZE.x + 0.36, 0.16, BOARD_SIZE.y + 0.36)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("3b2013")
	rim_mat.metallic = 0.08
	rim_mat.roughness = 0.62
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.position.y = -0.17
	add_child(rim)

func _build_hex_overlay() -> void:
	grid_overlay = MeshInstance3D.new()
	grid_overlay.name = "HexGridOverlay"
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.94, 0.72, 0.28, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for column in range(ZargosRules.BOARD_COLUMNS):
		for row in range(ZargosRules.BOARD_ROWS):
			var center := hex_to_world(Vector2i(column, row)) + Vector3(0, 0.125, 0)
			for side in range(6):
				var a := deg_to_rad(60.0 * side + 30.0)
				var b := deg_to_rad(60.0 * (side + 1) + 30.0)
				mesh.surface_add_vertex(center + Vector3(cos(a) * HEX_RADIUS, 0, sin(a) * HEX_RADIUS))
				mesh.surface_add_vertex(center + Vector3(cos(b) * HEX_RADIUS, 0, sin(b) * HEX_RADIUS))
	mesh.surface_end()
	grid_overlay.mesh = mesh
	add_child(grid_overlay)

func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_pitch = Node3D.new()
	camera_rig.add_child(camera_pitch)
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.near = 0.1
	camera.far = 80.0
	camera_pitch.add_child(camera)
	_update_camera()

func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -28, 0)
	sun.light_color = Color("ffd7a1")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-5, 5, 4)
	fill.light_color = Color("8c9fd0")
	fill.light_energy = 2.0
	fill.omni_range = 18.0
	add_child(fill)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 18)
	panel.custom_minimum_size = Vector2(450, 164)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("23150fdd")
	style.border_color = Color("b98b42")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	panel.add_child(stack)
	var title := Label.new()
	title.text = "ZARGO'S LORDS"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("e4b656"))
	stack.add_child(title)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	stack.add_child(status_label)
	details_label = Label.new()
	details_label.text = "Seleziona una pedina attiva, poi un esagono di destinazione."
	details_label.add_theme_color_override("font_color", Color("dfd0b7"))
	stack.add_child(details_label)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 14)
	score_label.add_theme_color_override("font_color", Color("cbb68f"))
	stack.add_child(score_label)
	var buttons := HBoxContainer.new()
	stack.add_child(buttons)
	var next := Button.new()
	next.text = "Fase successiva"
	next.pressed.connect(_on_next_phase)
	buttons.add_child(next)
	var battle := Button.new()
	battle.text = "Risolvi scontro"
	battle.pressed.connect(_on_resolve_battle)
	buttons.add_child(battle)
	var reset_view := Button.new()
	reset_view.text = "Centra vista"
	reset_view.pressed.connect(_reset_camera)
	buttons.add_child(reset_view)
	var grid_button := CheckButton.new()
	grid_button.text = "Griglia"
	grid_button.button_pressed = true
	grid_button.toggled.connect(func(value: bool): grid_overlay.visible = value)
	buttons.add_child(grid_button)

	event_label = Label.new()
	event_label.position = Vector2(20, 194)
	event_label.size = Vector2(640, 32)
	event_label.add_theme_font_size_override("font_size", 16)
	event_label.add_theme_color_override("font_color", Color("f0c977"))
	layer.add_child(event_label)

	var help := Label.new()
	help.text = "Rotazione: tasto destro  •  Spostamento: tasto centrale  •  Zoom: rotella  •  Selezione: sinistro"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -42
	help.offset_bottom = -12
	help.add_theme_color_override("font_color", Color("f3dfbd"))
	layer.add_child(help)

func _spawn_demo_armies() -> void:
	var homes := {
		&"Cavalieri": Vector2i(3, 3), &"Draghi": Vector2i(14, 3),
		&"Alati": Vector2i(3, 8), &"Monaci": Vector2i(14, 8)
	}
	for faction in ZargosRules.FACTIONS:
		var base: Vector2i = homes[faction]
		var index := 0
		for unit_type in ZargosRules.UNIT_TYPES[faction].keys():
			var offset := Vector2i(index % 2, index / 2)
			_spawn_unit(faction, unit_type, base + offset)
			index += 1

func _spawn_cities() -> void:
	var locations := {
		&"Cavalieri": [Vector2i(1, 1), Vector2i(3, 1), Vector2i(5, 1), Vector2i(1, 3), Vector2i(3, 5), Vector2i(5, 3)],
		&"Draghi": [Vector2i(12, 1), Vector2i(14, 1), Vector2i(16, 1), Vector2i(12, 3), Vector2i(14, 5), Vector2i(16, 3)],
		&"Alati": [Vector2i(1, 8), Vector2i(3, 10), Vector2i(5, 10), Vector2i(1, 10), Vector2i(3, 7), Vector2i(5, 8)],
		&"Monaci": [Vector2i(12, 10), Vector2i(14, 10), Vector2i(16, 10), Vector2i(12, 8), Vector2i(14, 6), Vector2i(16, 8)],
	}
	for faction in ZargosRules.FACTIONS:
		for city_hex in locations[faction]:
			var city := CardboardCity.new()
			add_child(city)
			city.setup(faction, city_hex)
			city.position = hex_to_world(city_hex) + Vector3(0, 0.19, 0)
			state.register_city(faction)

func _spawn_unit(faction: StringName, unit_type: StringName, hex: Vector2i) -> void:
	var unit := CardboardUnit.new()
	add_child(unit)
	unit.setup(faction, unit_type, hex)
	unit.position = hex_to_world(hex) + Vector3(0, 0.18, 0)

func hex_to_world(hex: Vector2i) -> Vector3:
	var width := HEX_RADIUS * sqrt(3.0)
	var x := (hex.x - (ZargosRules.BOARD_COLUMNS - 1) * 0.5) * width
	var z := (hex.y - (ZargosRules.BOARD_ROWS - 1) * 0.5) * HEX_RADIUS * 1.5
	if hex.x & 1:
		z += HEX_RADIUS * 0.75
	return Vector3(x, 0.0, z)

func world_to_hex(point: Vector3) -> Vector2i:
	var width := HEX_RADIUS * sqrt(3.0)
	var column := int(round(point.x / width + (ZargosRules.BOARD_COLUMNS - 1) * 0.5))
	var z_offset := HEX_RADIUS * 0.75 if column & 1 else 0.0
	var row := int(round((point.z - z_offset) / (HEX_RADIUS * 1.5) + (ZargosRules.BOARD_ROWS - 1) * 0.5))
	return Vector2i(clampi(column, 0, ZargosRules.BOARD_COLUMNS - 1), clampi(row, 0, ZargosRules.BOARD_ROWS - 1))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = maxf(4.0, camera_distance - 0.9)
			_update_camera()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = minf(24.0, camera_distance + 0.9)
			_update_camera()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pick_at(event.position)
	elif event is InputEventMouseMotion:
		if orbiting:
			orbit_yaw -= event.relative.x * 0.008
			orbit_pitch = clampf(orbit_pitch - event.relative.y * 0.008, -1.45, -0.28)
			_update_camera()
		elif panning:
			var factor := camera_distance * 0.0018
			camera_rig.position += camera_rig.global_basis.x * -event.relative.x * factor
			camera_rig.position += Vector3(camera_rig.global_basis.z.x, 0, camera_rig.global_basis.z.z).normalized() * -event.relative.y * factor
	if event.is_action_pressed("cancel_action"):
		_select_unit(null)

func _pick_at(screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.collider
	if collider is CardboardUnit:
		if selected and collider != selected and state.phase == ZargosRules.Phase.COMBAT:
			_resolve_attack(selected, collider)
		else:
			_select_unit(collider)
	elif collider is CardboardCity:
		_handle_city_click(collider)
	elif collider.has_meta("is_board") and selected:
		_try_move_selected(world_to_hex(hit.position))

func _select_unit(unit: CardboardUnit) -> void:
	if selected:
		selected.set_selected(false)
	selected = unit
	if not selected:
		details_label.text = "Nessuna pedina selezionata."
		return
	selected.set_selected(true)
	details_label.text = "%s • %s • Movimento %d • Combattimento %d%s" % [selected.faction, selected.unit_type, selected.movement, selected.combat, " • " + selected.ability if selected.ability else ""]

func _try_move_selected(destination: Vector2i) -> void:
	if state.phase != ZargosRules.Phase.MOVEMENT:
		_show_event("Le pedine si muovono soltanto durante la fase Movimento.")
		return
	if selected.faction != state.active_faction():
		_show_event("È il turno dei %s." % state.active_faction())
		return
	if selected.moved:
		_show_event("Questa pedina ha già mosso nel turno corrente.")
		return
	var flying := selected.ability == "Volo"
	var movement_cost := board_data.find_movement_cost(selected.hex, destination, selected.movement, flying, func(hex: Vector2i): return _unit_at(hex) != null)
	if movement_cost < 0:
		_show_event("Destinazione non raggiungibile con il movimento e il terreno disponibili.")
		return
	if _unit_at(destination):
		_show_event("L'esagono è già occupato.")
		return
	selected.hex = destination
	selected.position = hex_to_world(destination) + Vector3(0, 0.18, 0)
	selected.moved = true
	var terrain_name: String = String(ZargosRules.Terrain.keys()[board_data.terrain_at(destination)]).capitalize()
	_show_event("%s spostato • costo %d/%d • terreno %s." % [selected.unit_type, movement_cost, selected.movement, terrain_name])

func _unit_at(hex: Vector2i) -> CardboardUnit:
	for child in get_children():
		if child is CardboardUnit and child.visible and child.hex == hex:
			return child
	return null

func _handle_city_click(city: CardboardCity) -> void:
	if state.phase == ZargosRules.Phase.COMBAT and selected and city.faction != selected.faction:
		_resolve_siege(selected, city)
		return
	if state.phase != ZargosRules.Phase.MOVEMENT:
		_show_event("Le città si gestiscono durante Movimento o Combattimento.")
		return
	if not selected:
		_release_garrison(city)
		return
	_try_enter_city(city)

func _try_enter_city(city: CardboardCity) -> void:
	if not selected:
		return
	if selected.faction != state.active_faction() or selected.moved:
		_show_event("La pedina selezionata non può muovere ora.")
		return
	var distance := ZargosRules.hex_distance(selected.hex, city.hex)
	if distance > selected.movement:
		_show_event("La città è oltre il movimento massimo della pedina.")
		return
	if _unit_at(city.hex) and _unit_at(city.hex) != selected:
		_show_event("La città è già occupata da una pedina.")
		return
	var old_owner := city.faction
	if old_owner != selected.faction and not city.garrison.is_empty():
		_show_event("La città è difesa: devi assediarla durante il Combattimento.")
		return
	selected.hex = city.hex
	selected.moved = true
	if old_owner != selected.faction:
		selected.position = hex_to_world(city.hex) + Vector3(0, 0.34, 0)
		city.change_owner(selected.faction)
		state.capture_city(old_owner, selected.faction)
		_show_event("I %s conquistano una città dei %s." % [selected.faction, old_owner])
	else:
		if city.add_to_garrison(selected):
			_show_event("%s entra nella guarnigione (%d/4)." % [selected.unit_type, city.garrison.size()])
			_select_unit(null)
		else:
			selected.position = hex_to_world(city.hex) + Vector3(0, 0.34, 0)
			_show_event("Guarnigione completa: la pedina resta sopra la città.")

func _release_garrison(city: CardboardCity) -> void:
	if city.faction != state.active_faction():
		_show_event("Puoi gestire solo le città del popolo attivo.")
		return
	var unit := city.release_first()
	if not unit:
		_show_event("La città non contiene una guarnigione.")
		return
	var destinations := _hex_neighbors(city.hex).filter(func(hex: Vector2i): return _is_on_board(hex) and not _unit_at(hex))
	if destinations.is_empty():
		city.add_to_garrison(unit)
		_show_event("Nessun esagono libero per far uscire la guarnigione.")
		return
	unit.hex = destinations[0]
	unit.position = hex_to_world(unit.hex) + Vector3(0, 0.18, 0)
	unit.moved = true
	_show_event("%s esce dalla guarnigione." % unit.unit_type)

func _resolve_siege(attacker: CardboardUnit, city: CardboardCity) -> void:
	if attacker.faction != state.active_faction() or attacker.acted:
		_show_event("L'attaccante non può agire ora.")
		return
	if ZargosRules.hex_distance(attacker.hex, city.hex) != 1:
		_show_event("Per assediare una città bisogna essere adiacenti.")
		return
	if city.garrison.is_empty():
		var old_owner := city.faction
		city.change_owner(attacker.faction)
		state.capture_city(old_owner, attacker.faction)
		_show_event("Città indifesa conquistata dai %s." % attacker.faction)
		return
	attacker.acted = true
	var defense := city.garrison_strength()
	var die := rng.randi_range(1, 6)
	var result := ZargosRules.resolve_combat(attacker.combat, defense, die)
	var code: String = result.result
	if code in ["D1", "D3"]:
		code = "A1"
	_show_event("Assedio • dado %d • %d contro guarnigione %d: %s" % [die, attacker.combat, defense, code])
	if code in ["D5", "DE"]:
		for defeated in city.clear_garrison():
			_eliminate_unit(defeated)
		var old_owner := city.faction
		city.change_owner(attacker.faction)
		state.capture_city(old_owner, attacker.faction)
		_show_event(event_label.text + " • città conquistata")
	elif code == "AE":
		_eliminate_unit(attacker)
	elif code.begins_with("A"):
		_retreat_unit(attacker, _city_threat_proxy(city), int(code.right(1)))

func _city_threat_proxy(city: CardboardCity) -> CardboardUnit:
	# Unità temporanea non inserita nell'albero: serve solo come origine geometrica della fuga.
	var proxy := CardboardUnit.new()
	proxy.hex = city.hex
	return proxy

func _on_next_phase() -> void:
	var old_faction := state.active_faction()
	state.advance_phase()
	if state.phase == ZargosRules.Phase.ALLIANCES or state.active_faction() != old_faction:
		for child in get_children():
			if child is CardboardUnit:
				child.reset_turn()
	_select_unit(null)

func _on_resolve_battle() -> void:
	if state.phase != ZargosRules.Phase.COMBAT or not selected:
		_show_event("Seleziona un attaccante durante la fase Combattimento.")
		return
	var target := _find_adjacent_enemy(selected)
	if not target:
		_show_event("Nessun nemico adiacente alla pedina selezionata.")
		return
	_resolve_attack(selected, target)

func _resolve_attack(attacker: CardboardUnit, defender: CardboardUnit) -> void:
	if attacker.faction != state.active_faction():
		_show_event("È il turno dei %s." % state.active_faction())
		return
	if attacker.faction == defender.faction:
		_show_event("Non puoi attaccare una pedina del tuo popolo.")
		return
	if attacker.acted:
		_show_event("Questa pedina ha già agito nella fase di combattimento.")
		return
	var distance := ZargosRules.hex_distance(attacker.hex, defender.hex)
	if distance > 1 and attacker.ability in ["Tiro", "Fiamme", "Visione"]:
		_resolve_ranged_attack(attacker, defender, distance)
		return
	if distance != 1:
		_show_event("Il combattimento normale richiede un nemico adiacente.")
		return
	attacker.acted = true
	var die := rng.randi_range(1, 6)
	var defender_strength := defender.combat + board_data.defense_bonus_at(defender.hex)
	var result := ZargosRules.resolve_combat(attacker.combat, defender_strength, die)
	_show_event("Dado %d • %s contro %s: %s [%s]" % [die, attacker.unit_type, defender.unit_type, result.text, result.result])
	match result.result:
		"DE": _eliminate_unit(defender)
		"AE": _eliminate_unit(attacker)
		"IMPOSSIBILE": return
		_:
			var retreating := defender if result.retreat > 0 else attacker
			var threat := attacker if result.retreat > 0 else defender
			_retreat_unit(retreating, threat, absi(result.retreat))

func _resolve_ranged_attack(attacker: CardboardUnit, defender: CardboardUnit, distance: int) -> void:
	var die := rng.randi_range(1, 6)
	attacker.acted = true
	match attacker.ability:
		"Tiro":
			if distance > 8:
				_show_event("Bersaglio oltre la gittata massima degli arcieri.")
				attacker.acted = false
				return
			_apply_ranged_hits(defender, die, ZargosRules.arrow_hits(die, distance), "Frecce")
		"Fiamme":
			if distance > 5:
				_show_event("Bersaglio oltre la gittata massima delle fiamme.")
				attacker.acted = false
				return
			_apply_ranged_hits(defender, die, ZargosRules.fire_hits(die, distance), "Fiamme")
		"Visione":
			if distance > 5:
				_show_event("Bersaglio oltre la gittata massima della visione.")
				attacker.acted = false
				return
			var retreat := ZargosRules.vision_retreat(die, distance, defender.movement)
			_show_event("Visione • dado %d • distanza %d: %s arretra di %d" % [die, distance, defender.unit_type, retreat])
			if retreat > 0:
				_retreat_unit(defender, attacker, retreat)

func _apply_ranged_hits(defender: CardboardUnit, die: int, hits: int, attack_name: String) -> void:
	defender.ranged_hits += hits
	var required := maxi(1, defender.combat)
	_show_event("%s • dado %d: %d colpi su %s (%d/%d)" % [attack_name, die, hits, defender.unit_type, defender.ranged_hits, required])
	if defender.ranged_hits >= required:
		_show_event(event_label.text + " • bersaglio eliminato")
		_eliminate_unit(defender)

func _retreat_unit(unit: CardboardUnit, threat: CardboardUnit, distance: int) -> void:
	var current := unit.hex
	for step in range(distance):
		var options := _hex_neighbors(current)
		options = options.filter(func(hex: Vector2i): return _is_on_board(hex) and not _unit_at(hex))
		options.sort_custom(func(a: Vector2i, b: Vector2i): return ZargosRules.hex_distance(a, threat.hex) > ZargosRules.hex_distance(b, threat.hex))
		if options.is_empty() or ZargosRules.hex_distance(options[0], threat.hex) <= ZargosRules.hex_distance(current, threat.hex):
			_show_event(event_label.text + " • Fuga bloccata: pedina eliminata")
			_eliminate_unit(unit)
			return
		current = options[0]
	unit.hex = current
	var tween := create_tween()
	tween.tween_property(unit, "position", hex_to_world(current) + Vector3(0, 0.18, 0), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _eliminate_unit(unit: CardboardUnit) -> void:
	if selected == unit:
		selected = null
	var tween := create_tween()
	tween.tween_property(unit, "scale", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(unit.queue_free)

func _hex_neighbors(hex: Vector2i) -> Array[Vector2i]:
	var offsets_even: Array[Vector2i] = [Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
	var offsets_odd: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var output: Array[Vector2i] = []
	for offset in (offsets_odd if hex.x & 1 else offsets_even):
		output.append(hex + offset)
	return output

func _is_on_board(hex: Vector2i) -> bool:
	return hex.x >= 0 and hex.y >= 0 and hex.x < ZargosRules.BOARD_COLUMNS and hex.y < ZargosRules.BOARD_ROWS

func _find_adjacent_enemy(unit: CardboardUnit) -> CardboardUnit:
	for child in get_children():
		if child is CardboardUnit and child.faction != unit.faction and ZargosRules.hex_distance(child.hex, unit.hex) == 1:
			return child
	return null

func _refresh_ui() -> void:
	status_label.text = state.summary()
	score_label.text = "Città: " + state.city_score()
	if state.game_over:
		_show_event("Fine della partita • Vincitori: %s" % ", ".join(state.winners()))

func _show_event(message: String) -> void:
	event_label.text = message

func _reset_camera() -> void:
	camera_rig.position = Vector3.ZERO
	orbit_yaw = 0.0
	orbit_pitch = -0.82
	camera_distance = 12.8
	_update_camera()

func _update_camera() -> void:
	camera_rig.rotation.y = orbit_yaw
	camera_pitch.rotation.x = orbit_pitch
	camera.position = Vector3(0, 0, camera_distance)

