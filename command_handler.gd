@tool
class_name MCPCommandHandler
extends Node

var _mcp_server
var _command_processors = []

func initialize_command_processors(mcp_server):
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
	add_child(file_commands)

func handle_command(command: Dictionary) -> Dictionary:
	var command_type = command.get("command_type", "")
	var params = command.get("params", {})

	# Try each command processor until one handles the command
	for processor in _command_processors:
		var response = processor.process_command(command_type, params)
		if response.size() > 0:
			return response

	return {
		"status": "error",
		"message": "Unknown command: " + command_type
	}