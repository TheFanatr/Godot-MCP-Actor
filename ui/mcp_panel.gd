@tool
extends Control

var mcp_server  # Reference to the C# Main class
var status_label: Label
var port_input: SpinBox
var start_button: Button
var stop_button: Button
var connection_count_label: Label
var log_text: TextEdit

func _ready():
	status_label = $VBoxContainer/StatusContainer/StatusLabel
	port_input = $VBoxContainer/PortContainer/PortSpinBox
	start_button = $VBoxContainer/ButtonsContainer/StartButton
	stop_button = $VBoxContainer/ButtonsContainer/StopButton
	connection_count_label = $VBoxContainer/ConnectionsContainer/CountLabel
	log_text = $VBoxContainer/LogContainer/LogText

	start_button.pressed.connect(_on_start_button_pressed)
	stop_button.pressed.connect(_on_stop_button_pressed)
	port_input.value_changed.connect(_on_port_changed)

	# Find the MCP server instance
	await get_tree().process_frame
	_find_mcp_server()

	# Initial UI setup
	_update_ui()

func _find_mcp_server():
	# Try to find the Main.cs instance
	if Engine.has_meta("GodotMCP"):
		var plugin = Engine.get_meta("GodotMCP")
		# Check if it has the required methods instead of checking type
		if plugin.has_method("IsServerActive") and plugin.has_method("StartServer"):
			mcp_server = plugin
			_log_message("Found MCP server instance")

			# Connect signals
			mcp_server.connect("client_connected", Callable(self, "_on_client_connected"))
			mcp_server.connect("client_disconnected", Callable(self, "_on_client_disconnected"))
			mcp_server.connect("command_received", Callable(self, "_on_command_received"))

			# Update port input
			port_input.value = mcp_server.GetPort()

			_update_ui()
		else:
			_log_message("Error: Plugin instance does not have required methods")
	else:
		_log_message("Error: Could not find MCP server instance")

func _update_ui():
	if not mcp_server:
		status_label.text = "Server: Not initialized"
		start_button.disabled = true
		stop_button.disabled = true
		port_input.editable = true
		connection_count_label.text = "0"
		return

	var is_active = mcp_server.IsServerActive()

	status_label.text = "Server: " + ("Running" if is_active else "Stopped")
	start_button.disabled = is_active
	stop_button.disabled = not is_active
	port_input.editable = not is_active

	if is_active:
		connection_count_label.text = str(mcp_server.GetClientCount())
	else:
		connection_count_label.text = "0"

func _on_start_button_pressed():
	if mcp_server:
		var result = mcp_server.StartServer()
		if result == OK:
			_log_message("Server started on port " + str(mcp_server.GetPort()))
		else:
			_log_message("Failed to start server: " + str(result))
		_update_ui()

func _on_stop_button_pressed():
	if mcp_server:
		mcp_server.StopServer()
		_log_message("Server stopped")
		_update_ui()

func _on_port_changed(new_port: float):
	if mcp_server:
		mcp_server.SetPort(int(new_port))
		_log_message("Port changed to " + str(int(new_port)))

func _on_client_connected(client_id: int):
	_log_message("Client connected: " + str(client_id))
	_update_ui()

func _on_client_disconnected(client_id: int):
	_log_message("Client disconnected: " + str(client_id))
	_update_ui()

func _on_command_received(client_id: int, command: Dictionary):
	var command_type = command.get("type", "unknown")
	var command_id = command.get("commandId", "no-id")
	_log_message("Received command: " + command_type + " (ID: " + command_id + ") from client " + str(client_id))

func _log_message(message: String):
	var timestamp = Time.get_datetime_string_from_system()
	log_text.text += "[" + timestamp + "] " + message + "\n"
	# Auto-scroll to bottom
	log_text.scroll_vertical = log_text.get_line_count()