@tool
extends RefCounted

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _secret := ""
var _dispatcher: Callable
var _port := 9877
var _last_error := ""


func start(port: int, secret: String, dispatcher: Callable) -> Error:
	if secret.length() < 32:
		_last_error = "Bridge secret must contain at least 32 characters."
		return ERR_INVALID_PARAMETER

	stop()
	_port = port
	_secret = secret
	_dispatcher = dispatcher
	var error := _server.listen(port, "127.0.0.1")
	if error != OK:
		_last_error = "Could not bind 127.0.0.1:%d (error %d)." % [port, error]
		return error
	_last_error = ""
	return OK


func stop() -> void:
	for client in _clients:
		var peer: StreamPeerTCP = client.get("peer")
		if peer:
			peer.disconnect_from_host()
	_clients.clear()
	if _server.is_listening():
		_server.stop()


func is_running() -> bool:
	return _server.is_listening()


func port() -> int:
	return _port


func last_error() -> String:
	return _last_error


func poll() -> void:
	if not _server.is_listening():
		return

	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			_clients.append({"peer": peer, "buffer": ""})

	for index in range(_clients.size() - 1, -1, -1):
		var client := _clients[index]
		var peer: StreamPeerTCP = client.get("peer")
		if peer == null:
			_clients.remove_at(index)
			continue

		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(index)
			continue

		var available := peer.get_available_bytes()
		if available <= 0:
			continue

		var received := peer.get_data(available)
		if received[0] != OK:
			_clients.remove_at(index)
			continue

		client["buffer"] = String(client.get("buffer", "")) + received[1].get_string_from_utf8()
		var buffer := String(client["buffer"])

		while buffer.contains("\n"):
			var newline := buffer.find("\n")
			var line := buffer.substr(0, newline).strip_edges()
			buffer = buffer.substr(newline + 1)
			if not line.is_empty():
				_handle_request(peer, line)
		client["buffer"] = buffer


func _handle_request(peer: StreamPeerTCP, line: String) -> void:
	var parsed = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send(peer, {
			"request_id": "",
			"ok": false,
			"error": "invalid_json_object",
		})
		return

	var request: Dictionary = parsed
	var request_id := String(request.get("request_id", ""))
	if not _constant_time_string_equal(String(request.get("secret", "")), _secret):
		_send(peer, {
			"request_id": request_id,
			"ok": false,
			"error": "unauthorized_bridge_request",
		})
		return

	var operation := String(request.get("operation", ""))
	var params = request.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		_send(peer, {
			"request_id": request_id,
			"ok": false,
			"error": "params_must_be_object",
		})
		return

	if not _dispatcher.is_valid():
		_send(peer, {
			"request_id": request_id,
			"ok": false,
			"error": "dispatcher_unavailable",
		})
		return

	var result = _dispatcher.call(operation, params)
	if typeof(result) != TYPE_DICTIONARY:
		_send(peer, {
			"request_id": request_id,
			"ok": false,
			"error": "dispatcher_returned_invalid_result",
		})
		return

	if result.has("__nexora_error"):
		_send(peer, {
			"request_id": request_id,
			"ok": false,
			"error": String(result.get("__nexora_error")),
		})
		return

	_send(peer, {
		"request_id": request_id,
		"ok": true,
		"result": result,
	})


func _send(peer: StreamPeerTCP, payload: Dictionary) -> void:
	var line := JSON.stringify(payload) + "\n"
	peer.put_data(line.to_utf8_buffer())


func _constant_time_string_equal(left: String, right: String) -> bool:
	var a := left.to_utf8_buffer()
	var b := right.to_utf8_buffer()
	var max_size := maxi(a.size(), b.size())
	var diff := a.size() ^ b.size()
	for index in range(max_size):
		var av := a[index] if index < a.size() else 0
		var bv := b[index] if index < b.size() else 0
		diff |= av ^ bv
	return diff == 0
