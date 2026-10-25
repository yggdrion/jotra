class_name MetricsServer
extends Node
## Plain HTTP endpoint for Prometheus scrapes (vector on the vServer). Every request, whatever
## its path, gets source.call() as the body.

var source: Callable

var _tcp := TCPServer.new()
var _clients: Array[StreamPeerTCP] = []


func start(port: int) -> Error:
	return _tcp.listen(port)


# ponytail: answers once the first request bytes arrive and never waits for the rest; fine for
# a scraper on localhost, not for anything public.
func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		_clients.append(_tcp.take_connection())
	for client: StreamPeerTCP in _clients.duplicate():
		client.poll()
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
		elif client.get_available_bytes() > 0:
			client.get_data(client.get_available_bytes())
			var body: PackedByteArray = (source.call() as String).to_utf8_buffer()
			var head := (
				"HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\n"
				+ "Content-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
			)
			client.put_data(head.to_ascii_buffer() + body)
			client.disconnect_from_host()
			_clients.erase(client)
