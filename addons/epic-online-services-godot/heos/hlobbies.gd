extends Node


#region Public vars

## The maximum number of lobbies to return in search calls.[br]
## Except for [method create_search] and [method search_async]
var max_search_results = 25

## Whether to show the lobby in the user's presence
var presence_enabled = true

## Local RTC options for the lobby[br]
## (Optional) You can override any of the below keys.[br]
## A [Dictionary] with keys:[br]
## - flags: a bitwise-or union of [enum EOS.RTC.JoinRoomFlags][br]
## - use_manual_audio_input: [bool][br]
## - use_manual_audio_output: [bool][br]
## - local_audio_device_input_starts_muted: [bool]
var local_rtc_options = {
	flags = EOS.RTC.JoinRoomFlags.EnableDataChannel
}

#endregion


#region Private vars

var _log = HLog.logger("HLobbies")

#endregion


#region Public methods

## Create a new lobby. Returns [HLobby] or [null]
func create_lobby_async(opts: EOS.Lobby.CreateLobbyOptions) -> HLobby:
	_log.debug("Creating lobby...")
	EOS.Lobby.LobbyInterface.create_lobby(opts)

	var ret = await IEOS.lobby_interface_create_lobby_callback
	if not EOS.is_success(ret):
		_log.error("Failed to create lobby: %s" % EOS.result_str(ret))
		return null

	_log.debug("Lobby created: lobby_id=%s" % ret.lobby_id)

	var lobby = HLobby.new()
	lobby.init_from_id(ret.lobby_id)
	return lobby


## Join an existing lobby by id. It should only be used if the lobby has had Join-by-ID enabled.
## Additionally, Join-by-ID should only be enabled to support native invites on an integrated platform.
## Returns [HLobby] or [null]
func join_by_id_async(lobby_id: String) -> HLobby:
	_log.debug("Joining lobby by id: lobby_id=%s" % lobby_id)

	var opts = EOS.Lobby.JoinLobbyByIdOptions.new()
	opts.lobby_id = lobby_id
	opts.presence_enabled = presence_enabled
	opts.local_rtc_options = local_rtc_options
	EOS.Lobby.LobbyInterface.join_lobby_by_id(opts)

	var ret = await IEOS.lobby_interface_join_lobby_by_id_callback
	if not EOS.is_success(ret):
		_log.error("Failed to join lobby: result_code=%s" % EOS.result_str(ret))
		return null

	_log.debug("Lobby joined: lobby_id=%s" % lobby_id)

	var lobby = HLobby.new()
	lobby.init_from_id(lobby_id)
	return lobby


## Join an existing lobby, for example one returned from a search.
## Returns [HLobby] or [null]
func join_async(lobby: HLobby):
	if not lobby:
		return null
	_log.debug("Joining lobby...")

	var opts = EOS.Lobby.JoinLobbyOptions.new()
	opts.lobby_details = lobby._lobby_details
	opts.presence_enabled = presence_enabled
	opts.local_rtc_options = local_rtc_options
	EOS.Lobby.LobbyInterface.join_lobby(opts)

	var ret = await IEOS.lobby_interface_join_lobby_callback
	if not EOS.is_success(ret):
		_log.error("Failed to join lobby: result_code=%s" % EOS.result_str(ret))
		return null

	_log.debug("Lobby joined: lobby_id=%s" % ret.lobby_id)

	var new_lobby = HLobby.new()
	new_lobby.init_from_id(ret.lobby_id)
	return new_lobby


## Search for public lobbies that a user is in.
## Returns [Array] of [HLobby] or null
func search_by_product_user_id_async(product_user_id: String):
	_log.debug("Searching for lobbies by product user id")
	var opts = EOS.Lobby.CreateLobbySearchOptions.new()
	opts.max_results = max_search_results

	var search: EOSGLobbySearch = create_search(opts)
	if not search:
		return null

	var set_result: int = search.set_target_user_id(product_user_id)
	if not EOS.is_success(set_result):
		_log.error("Failed to set target user for lobby search: result_code=%s" % EOS.result_str(set_result))
		return null

	return await search_async(search)


## Search for public lobbies based on attributes.[br]
## The input argument can either be a [Dictionary] or an [Array] of [Dictionary].[br]
## There is an implicit AND operation when multiple search attributes are provided.[br]
## Each search attribute must have:[br]
## - key: [String] - the attribute key[br]
## - value: [String], [bool], [int], or [float] - the attribute value[br]
## - comparison: [enum EOS.ComparisonOp] - optional; defaults to Equal
## Returns [Array] of [HLobby] or null. A failed SetParameter is returned as null.
func search_by_attribute_async(attributes):
	if typeof(attributes) == TYPE_DICTIONARY:
		attributes = [attributes]

	if not (attributes is Array) or attributes.is_empty():
		_log.error("Lobby attribute search requires at least one search attribute.")
		return null

	_log.debug("Searching for lobbies by %d attribute filter(s)." % attributes.size())
	var opts = EOS.Lobby.CreateLobbySearchOptions.new()
	opts.max_results = max_search_results

	var search: EOSGLobbySearch = create_search(opts)
	if not search:
		return null

	for attr_variant in attributes:
		if not (attr_variant is Dictionary):
			_log.error("Invalid lobby search filter: expected a Dictionary.")
			return null

		var attr: Dictionary = attr_variant
		var key: String = str(attr.get("key", "")).strip_edges()
		if key.is_empty() or not attr.has("value"):
			_log.error("Invalid lobby search filter: key and value are required.")
			return null

		var value: Variant = attr.get("value")
		var value_type: int = typeof(value)
		if value_type not in [TYPE_STRING, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
			_log.error("Invalid lobby search value type for key=%s. Use String, bool, int, or float." % key)
			return null

		var comparison: int = int(attr.get("comparison", EOS.ComparisonOp.Equal))
		var set_result: int = search.set_parameter(key, value, comparison)
		if not EOS.is_success(set_result):
			_log.error(
				"Failed to set lobby search parameter: key=%s comparison=%d result_code=%s" %
				[key, comparison, EOS.result_str(set_result)]
			)
			return null

	return await search_async(search)


## Search for lobby by id. At most one lobby will be returned.
## Returns [Array] of [HLobby] or null
func search_by_lobby_id_async(lobby_id: String):
	_log.debug("Searching for lobby by id.")
	var opts = EOS.Lobby.CreateLobbySearchOptions.new()
	opts.max_results = max_search_results

	var search: EOSGLobbySearch = create_search(opts)
	if not search:
		return null

	var set_result: int = search.set_lobby_id(lobby_id)
	if not EOS.is_success(set_result):
		_log.error("Failed to set lobby id for search: result_code=%s" % EOS.result_str(set_result))
		return null

	return await search_async(search)


## Search for lobby by bucket id.
## Returns [Array] of [HLobby] or null
func search_by_bucket_id_async(bucket_id: String):
	_log.debug("Searching for lobbies by bucket id: bucket_id=%s" % bucket_id)
	return await search_by_attribute_async({
		key = EOS.Lobby.SEARCH_BUCKET_ID,
		value = bucket_id,
		comparison = EOS.ComparisonOp.Equal
	})


## (Advanced) Create a new lobby search. Returns [EOSGLobbySearch] or null.
## Use [method search_async] to perform the search.
func create_search(opts: EOS.Lobby.CreateLobbySearchOptions):
	_log.debug("Creating lobby search...")

	var create_ret = EOS.Lobby.LobbyInterface.create_lobby_search(opts)
	if not EOS.is_success(create_ret):
		_log.error("Failed to create lobby search: result_code=%s" % EOS.result_str(create_ret))
		return null

	return create_ret.lobby_search


## (Advanced) Perform the lobby search. Returns [Array] of [HLobby] or null.
func search_async(lobby_search: EOSGLobbySearch):
	if lobby_search == null:
		_log.error("Cannot perform a null lobby search.")
		return null

	_log.debug("Submitting EOS lobby search...")
	# EOSG 2.3.1's find() wrapper returns void; completion and its EOS result
	# arrive through IEOS.lobby_search_find_callback.
	lobby_search.find(HAuth.product_user_id)

	var search_ret = await IEOS.lobby_search_find_callback
	if not EOS.is_success(search_ret):
		_log.error("Failed to search for lobbies: result_code=%s" % EOS.result_str(search_ret))
		return null

	var count: int = lobby_search.get_search_result_count()
	_log.debug("Found lobbies: count=%s" % count)

	var lobbies: Array[HLobby] = []
	for search_idx in count:
		var copy_ret = lobby_search.copy_search_result_by_index(search_idx)
		if not EOS.is_success(copy_ret):
			_log.error("Failed to copy lobby search result index=%d: result_code=%s" % [search_idx, EOS.result_str(copy_ret)])
			continue

		var details: Variant = copy_ret.get("lobby_details")
		if details == null:
			_log.error("EOS returned a successful search-result copy without lobby details (index=%d)." % search_idx)
			continue

		var lobby = HLobby.new()
		lobby._init_from_details(details)
		if not lobby.is_valid():
			_log.error("EOS search result did not contain a valid lobby id (index=%d)." % search_idx)
			continue

		lobbies.append(lobby)

	return lobbies

#endregion
