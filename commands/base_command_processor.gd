@tool
class_name MCPBaseCommandProcessor
extends Node

# Must be implemented by subclasses
# Returns a Dictionary with either a success result or an error message
func process_command(command_type: String, params: Dictionary) -> Dictionary:
	push_error("BaseCommandProcessor.process_command called directly")
	return _create_error_response("BaseCommandProcessor.process_command called directly")

# Helper functions common to all command processors
func _create_success_response(result: Dictionary) -> Dictionary:
	return {
		"status": "success",
		"result": result
	}

func _create_error_response(message: String) -> Dictionary:
	return {
		"status": "error",
		"message": message
	}

# Common utility methods
func _get_editor_node(path: String) -> Node:
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		print("GodotMCPPlugin not found in Engine metadata")
		return null

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	if not edited_scene_root:
		print("No edited scene found")
		return null

	# Handle absolute paths
	if path == "/root" or path == "":
		return edited_scene_root

	if path.begins_with("/root/"):
		path = path.substr(6)  # Remove "/root/"
	elif path.begins_with("/"):
		path = path.substr(1)  # Remove leading "/"

	# Try to find node as child of edited scene root
	return edited_scene_root.get_node_or_null(path)

# Helper function to mark a scene as modified
func _mark_scene_modified() -> void:
	# Find the plugin by looking for the command handler's parent
	var command_handler = get_parent()
	var plugin = command_handler.get_parent()
	if not plugin or not plugin.has_method("get_editor_interface"):
		print("GodotMCPPlugin not found or invalid")
		return

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	if edited_scene_root:
		# This internally marks the scene as modified in the editor
		editor_interface.mark_scene_as_unsaved()

# Helper function to access the EditorUndoRedoManager
func _get_undo_redo():
	# Find the plugin by looking for the command handler's parent
	var command_handler = get_parent()
	var plugin = command_handler.get_parent()
	if not plugin or not plugin.has_method("get_undo_redo"):
		print("Cannot access UndoRedo from plugin")
		return null

	return plugin.get_undo_redo()

# Helper function to parse property values from string to proper Godot types
func _parse_property_value(value):
	# Only try to parse strings that look like they could be Godot types
	if typeof(value) == TYPE_STRING and (
		value.begins_with("Vector") or
		value.begins_with("Transform") or
		value.begins_with("Rect") or
		value.begins_with("Color") or
		value.begins_with("Quat") or
		value.begins_with("Basis") or
		value.begins_with("Plane") or
		value.begins_with("AABB") or
		value.begins_with("Projection") or
		value.begins_with("Callable") or
		value.begins_with("Signal") or
		value.begins_with("PackedVector") or
		value.begins_with("PackedString") or
		value.begins_with("PackedFloat") or
		value.begins_with("PackedInt") or
		value.begins_with("PackedColor") or
		value.begins_with("PackedByteArray") or
		value.begins_with("Dictionary") or
		value.begins_with("Array")
	):
		var expression = Expression.new()
		var error = expression.parse(value, [])

		if error == OK:
			var result = expression.execute([], null, true)
			if not expression.has_execute_failed():
				print("Successfully parsed %s as %s" % [value, result])
				return result
			else:
				print("Failed to execute expression for: %s" % value)
		else:
			print("Failed to parse expression: %s (Error: %d)" % [value, error])

	# Otherwise, return value as is
	return value
