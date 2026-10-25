class_name FirebaseOnline
extends Node

signal authenticated
signal room_created(code: String, data: Dictionary)
signal room_joined(code: String, data: Dictionary)
signal snapshot_received(data: Dictionary)
signal online_error(message: String)

const AUTH_ENDPOINT := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key="

var database_url := ""
var api_key := ""
var id_token := ""
var room_code := ""
var last_revision := -1
var polling := false
var poll_interval := 2.0
var _poll_timer: Timer

func _ready() -> void:
	_poll_timer = Timer.new()
	_poll_timer.one_shot = false
	_poll_timer.wait_time = poll_interval
	_poll_timer.timeout.connect(_poll_room)
	add_child(_poll_timer)

func configure(p_database_url: String, p_api_key: String) -> bool:
	database_url = p_database_url.strip_edges().trim_suffix("/")
	api_key = p_api_key.strip_edges()
	if not database_url.begins_with("https://") or api_key.is_empty():
		online_error.emit("Configurazione Firebase non valida: servono Database URL HTTPS e Web API key.")
		return false
	return true

func authenticate_anonymously() -> void:
	if database_url.is_empty() or api_key.is_empty():
		online_error.emit("Configura Firebase prima di collegarti.")
		return
	_request_json(
		HTTPClient.METHOD_POST,
		AUTH_ENDPOINT + api_key.uri_encode(),
		{"returnSecureToken": true},
		func(status: int, body: Variant):
			if status < 200 or status >= 300 or not body is Dictionary or not body.has("idToken"):
				online_error.emit(_firebase_error("Autenticazione anonima fallita", status, body))
				return
			id_token = String(body.idToken)
			authenticated.emit()
	)

func create_room(requested_code: String, initial_state: Dictionary) -> void:
	var code := normalize_room_code(requested_code)
	if not _validate_request(code):
		return
	var payload := {
		"version": 1,
		"created_at": Time.get_unix_time_from_system(),
		"revision": 0,
		"state": initial_state,
	}
	_request_json(HTTPClient.METHOD_PUT, _room_url(code), payload, func(status: int, body: Variant):
		if status < 200 or status >= 300:
			online_error.emit(_firebase_error("Creazione della stanza fallita", status, body))
			return
		room_code = code
		last_revision = 0
		room_created.emit(code, body if body is Dictionary else payload)
	)

func join_room(requested_code: String) -> void:
	var code := normalize_room_code(requested_code)
	if not _validate_request(code):
		return
	_request_json(HTTPClient.METHOD_GET, _room_url(code), {}, func(status: int, body: Variant):
		if status < 200 or status >= 300:
			online_error.emit(_firebase_error("Accesso alla stanza fallito", status, body))
			return
		if body == null or not body is Dictionary:
			online_error.emit("La stanza %s non esiste." % code)
			return
		room_code = code
		last_revision = int(body.get("revision", 0))
		room_joined.emit(code, body)
	)

func publish_snapshot(snapshot: Dictionary) -> void:
	if room_code.is_empty() or id_token.is_empty():
		online_error.emit("Non sei collegato a una stanza Firebase.")
		return
	var revision := maxi(last_revision + 1, int(Time.get_unix_time_from_system() * 1000.0))
	var payload := {"revision": revision, "state": snapshot, "updated_at": Time.get_unix_time_from_system()}
	_request_json(HTTPClient.METHOD_PATCH, _room_url(room_code), payload, func(status: int, body: Variant):
		if status < 200 or status >= 300:
			online_error.emit(_firebase_error("Sincronizzazione fallita", status, body))
			return
		last_revision = revision
	)

func start_polling() -> void:
	polling = true
	_poll_timer.start()

func stop_polling() -> void:
	polling = false
	_poll_timer.stop()

func _poll_room() -> void:
	if not polling or room_code.is_empty() or id_token.is_empty():
		return
	_request_json(HTTPClient.METHOD_GET, _room_url(room_code), {}, func(status: int, body: Variant):
		if status < 200 or status >= 300 or not body is Dictionary:
			return
		var revision := int(body.get("revision", -1))
		if revision > last_revision and body.get("state") is Dictionary:
			last_revision = revision
			snapshot_received.emit(body.state)
	)

func _validate_request(code: String) -> bool:
	if id_token.is_empty():
		online_error.emit("Autenticazione Firebase non completata.")
		return false
	if code.length() < 4:
		online_error.emit("Il codice stanza deve contenere almeno 4 caratteri.")
		return false
	return true

func _room_url(code: String) -> String:
	return "%s/games/%s.json?auth=%s" % [database_url, code.uri_encode(), id_token.uri_encode()]

func _request_json(method: HTTPClient.Method, url: String, payload: Dictionary, callback: Callable) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, raw_body: PackedByteArray):
		var parsed: Variant = null
		if not raw_body.is_empty():
			parsed = JSON.parse_string(raw_body.get_string_from_utf8())
		callback.call(response_code, parsed)
		request.queue_free()
	, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)
	var error := request.request(url, headers, method, body)
	if error != OK:
		request.queue_free()
		online_error.emit("Impossibile avviare la richiesta Firebase (%s)." % error_string(error))

static func normalize_room_code(value: String) -> String:
	var output := ""
	for character in value.to_upper():
		if character in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789":
			output += character
	return output.left(8)

static func generate_room_code() -> String:
	const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var output := ""
	for index in range(6):
		output += ALPHABET[randi() % ALPHABET.length()]
	return output

static func _firebase_error(prefix: String, status: int, body: Variant) -> String:
	var detail := ""
	if body is Dictionary and body.get("error") is Dictionary:
		detail = String(body.error.get("message", ""))
	return "%s (HTTP %d)%s" % [prefix, status, ": " + detail if not detail.is_empty() else ""]
