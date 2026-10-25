class_name ZargosGameState
extends RefCounted

signal state_changed
signal log_message(message: String)

var month := 1
var active_faction_index := 0
var phase := ZargosRules.Phase.ALLIANCES
var game_over := false
var cities := {&"Cavalieri": 0, &"Draghi": 0, &"Alati": 0, &"Monaci": 0}

func active_faction() -> StringName:
	return ZargosRules.FACTIONS[active_faction_index]

func phase_name() -> String:
	return ["Alleanze", "Movimento", "Combattimento"][phase]

func advance_phase() -> void:
	if game_over:
		return
	if phase < ZargosRules.Phase.COMBAT:
		phase += 1
	else:
		phase = ZargosRules.Phase.ALLIANCES
		active_faction_index += 1
		if active_faction_index >= ZargosRules.FACTIONS.size():
			active_faction_index = 0
			month += 1
			if month > ZargosRules.MONTH_LIMIT:
				month = ZargosRules.MONTH_LIMIT
				game_over = true
				log_message.emit("L'Anno di Zargo è terminato. Vince chi controlla più città.")
	state_changed.emit()

func summary() -> String:
	if game_over:
		return "Fine della partita • 25° mese"
	return "Mese %d/25  •  %s  •  %s" % [month, active_faction(), phase_name()]

func city_score() -> String:
	var parts: PackedStringArray = []
	for faction in ZargosRules.FACTIONS:
		parts.append("%s %d" % [faction, cities[faction]])
	return "  •  ".join(parts)

func register_city(owner: StringName) -> void:
	cities[owner] += 1

func capture_city(old_owner: StringName, new_owner: StringName) -> void:
	if old_owner == new_owner:
		return
	cities[old_owner] = maxi(0, cities[old_owner] - 1)
	cities[new_owner] += 1
	state_changed.emit()

func winners() -> PackedStringArray:
	var best := -1
	var result: PackedStringArray = []
	for faction in ZargosRules.FACTIONS:
		var score: int = cities[faction]
		if score > best:
			best = score
			result = PackedStringArray([String(faction)])
		elif score == best:
			result.append(String(faction))
	return result

