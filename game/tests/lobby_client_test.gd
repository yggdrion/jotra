extends GdUnitTestSuite
## LobbyClient without a lobby: its handling of lobby messages and ICE candidate lines. The
## whole path through a real lobby is in tools/run_network_test.py.


func test_candidate_summary() -> void:
	var line := "candidate:1 1 UDP 2122317823 192.168.1.5 54321 typ host"
	assert_str(LobbyClient.candidate_summary(line)).is_equal("host 192.168.1.5")
	line = "candidate:2 1 UDP 8331263 203.0.113.9 3479 typ relay raddr 0.0.0.0 rport 0"
	assert_str(LobbyClient.candidate_summary(line)).is_equal("relay 203.0.113.9")
	assert_str(LobbyClient.candidate_summary("garbage")).is_equal("")


func test_hosted_opens_the_room() -> void:
	var lobby := auto_free(LobbyClient.new()) as LobbyClient
	var codes: Array[String] = []
	lobby.room_opened.connect(func(code: String) -> void: codes.append(code))
	lobby.handle({"type": "hosted", "code": "ABCD", "ice": []})
	assert_array(codes).contains_exactly(["ABCD"])
	assert_str(lobby.code).is_equal("ABCD")


func test_joined_makes_a_client_peer_with_the_given_id() -> void:
	var lobby := auto_free(LobbyClient.new()) as LobbyClient
	var peers: Array[WebRTCMultiplayerPeer] = []
	lobby.peer_created.connect(func(peer: WebRTCMultiplayerPeer) -> void: peers.append(peer))
	lobby.handle({"type": "joined", "code": "ABCD", "id": 5, "ice": []})
	assert_int(peers.size()).is_equal(1)
	assert_int(peers[0].get_unique_id()).is_equal(5)
	assert_bool(peers[0].has_peer(LobbyClient.SERVER_ID)).is_true()


func test_errors_fail_once_with_a_readable_reason() -> void:
	var lobby := auto_free(LobbyClient.new()) as LobbyClient
	var reasons: Array[String] = []
	lobby.failed.connect(func(reason: String) -> void: reasons.append(reason))
	lobby.handle({"type": "error", "reason": "no room with that code"})
	lobby.handle({"type": "error", "reason": "again"})
	assert_array(reasons).contains_exactly(["No room with that code"])
