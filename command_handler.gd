@tool
class_name MCPCommandHandler
extends Node

var _mcp_server
var _command_processors = []

func _initialize_command_processors(mcp_server):
	_mcp_server = mcp_server

	# Create and add all command processors
	var node_commands = MCPNodeCommands.new()
	var script_commands = MCPScriptCommands.new()
	var scene_commands = MCPSceneCommands.new()
	var project_commands = MCPProjectCommands.new()
	var editor_commands = MCPEditorCommands.new()
	var editor_script_commands = MCPEditorScriptCommands.new()  # Add our new processor
	var file_commands = MCPFileCommands.new()  # Add new processor

	# Set server reference for all processors
	node_commands._websocket_server = _mcp_server
	script_commands._websocket_server = _mcp_server
	scene_commands._websocket_server = _mcp_server
	project_commands._websocket_server = _mcp_server
	editor_commands._websocket_server = _mcp_server
	editor_script_commands._websocket_server = _mcp_server
	file_commands._websocket_server = _mcp_server  # Set server reference

	# Add them to our processor list
	_command_processors.append(node_commands)
	_command_processors.append(script_commands)
	_command_processors.append(scene_commands)
	_command_processors.append(project_commands)
	_command_processors.append(editor_commands)
	_command_processors.append(editor_script_commands)
	_command_processors.append(file_commands)  # Add to processor list

	# Add them as children for proper lifecycle management
	add_child(node_commands)
	add_child(script_commands)
	add_child(scene_commands)
	add_child(project_commands)
	add_child(editor_commands)
	add_child(editor_script_commands)
	add_child(file_commands)  # Add as child

func _handle_command(client_id: int, command: Dictionary) -> void:
	var command_type = command.get("type", "")
	var params = command.get("params", {})
	var command_id = command.get("commandId", "")

	print("Processing command: %s" % command_type)

	# Try each processor until one handles the command
	for processor in _command_processors:
		if processor.process_command(client_id, command_type, params, command_id):
			return

	# If no processor handled the command, send an error
	_send_error(client_id, "Unknown command: %s" % command_type, command_id)

func _send_error(client_id: int, message: String, command_id: String) -> void:
	var response = {
		"status": "error",
		"message": message
	}

	if not command_id.is_empty():
		response["commandId"] = command_id

	_mcp_server.SendResponse(client_id, response)
	print("Error: %s" % message)
