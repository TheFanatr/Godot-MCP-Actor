@tool
class_name MCPNodeCommands
extends MCPBaseCommandProcessor

func process_command(command_type: String, params: Dictionary) -> Dictionary:
	match command_type:
		"create_node":
			return _create_node(params)
		"delete_node":
			return _delete_node(params)
		"update_node_property":
			return _update_node_property(params)
		"get_node_properties":
			return _get_node_properties(params)
		"list_nodes":
			return _list_nodes(params)
	# Return an empty dictionary to indicate command not handled
	return {}

func _create_node(params: Dictionary) -> Dictionary:
	var parent_path = params.get("parent_path", "/root")
	var node_type = params.get("node_type", "Node")
	var node_name = params.get("node_name", "NewNode")

	# Validation
	if not ClassDB.class_exists(node_type):
		return _create_error_response("Invalid node type: %s" % node_type)

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	if not edited_scene_root:
		return _create_error_response("No scene is currently being edited")

	# Get the parent node using the editor node helper
	var parent = _get_editor_node(parent_path)
	if not parent:
		return _create_error_response("Parent node not found: %s" % parent_path)

	# Create the node
	var node
	if ClassDB.can_instantiate(node_type):
		node = ClassDB.instantiate(node_type)
	else:
		return _create_error_response("Cannot instantiate node of type: %s" % node_type)

	if not node:
		return _create_error_response("Failed to create node of type: %s" % node_type)

	# Set the node name
	node.name = node_name

	# Add the node to the parent
	parent.add_child(node)

	# Set owner for proper serialization
	node.owner = edited_scene_root

	# Mark the scene as modified
	_mark_scene_modified()

	return _create_success_response({
		"node_path": parent_path + "/" + node_name
	})

func _delete_node(params: Dictionary) -> Dictionary:
	var node_path = params.get("node_path", "")

	# Validation
	if node_path.is_empty():
		return _create_error_response("Node path cannot be empty")

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	if not edited_scene_root:
		return _create_error_response("No scene is currently being edited")

	# Get the node using the editor node helper
	var node = _get_editor_node(node_path)
	if not node:
		return _create_error_response("Node not found: %s" % node_path)

	# Cannot delete the root node
	if node == edited_scene_root:
		return _create_error_response("Cannot delete the root node")

	# Get parent for operation
	var parent = node.get_parent()
	if not parent:
		return _create_error_response("Node has no parent: %s" % node_path)

	# Remove the node
	parent.remove_child(node)
	node.queue_free()

	# Mark the scene as modified
	_mark_scene_modified()

	return _create_success_response({
		"deleted_node_path": node_path
	})

func _update_node_property(params: Dictionary) -> Dictionary:
	var node_path = params.get("node_path", "")
	var property_name = params.get("property", "")
	var property_value = params.get("value")

	# Validation
	if node_path.is_empty():
		return _create_error_response("Node path cannot be empty")

	if property_name.is_empty():
		return _create_error_response("Property name cannot be empty")

	if property_value == null:
		return _create_error_response("Property value cannot be null")

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	# Get the node using the editor node helper
	var node = _get_editor_node(node_path)
	if not node:
		return _create_error_response("Node not found: %s" % node_path)

	# Check if the property exists
	if not property_name in node:
		return _create_error_response("Property %s does not exist on node %s" % [property_name, node_path])

	# Parse property value for Godot types
	var parsed_value = _parse_property_value(property_value)

	# Get current property value for undo
	var old_value = node.get(property_name)

	# Get undo/redo system
	var undo_redo = _get_undo_redo()
	if not undo_redo:
		# Fallback method if we can't get undo/redo
		node.set(property_name, parsed_value)
		_mark_scene_modified()
	else:
		# Use undo/redo for proper editor integration
		undo_redo.create_action("Update Property: " + property_name)
		undo_redo.add_do_property(node, property_name, parsed_value)
		undo_redo.add_undo_property(node, property_name, old_value)
		undo_redo.commit_action()

	# Mark the scene as modified
	_mark_scene_modified()

	return _create_success_response({
		"node_path": node_path,
		"property": property_name,
		"value": property_value,
		"parsed_value": str(parsed_value)
	})

func _get_node_properties(params: Dictionary) -> Dictionary:
	var node_path = params.get("node_path", "")

	# Validation
	if node_path.is_empty():
		return _create_error_response("Node path cannot be empty")

	# Get the node using the editor node helper
	var node = _get_editor_node(node_path)
	if not node:
		return _create_error_response("Node not found: %s" % node_path)

	# Get all properties
	var properties = {}
	var property_list = node.get_property_list()

	for prop in property_list:
		var name = prop["name"]
		if not name.begins_with("_"):  # Skip internal properties
			properties[name] = node.get(name)

	return _create_success_response({
		"node_path": node_path,
		"properties": properties
	})

func _list_nodes(params: Dictionary) -> Dictionary:
	var parent_path = params.get("parent_path", "/root")

	# Get the parent node using the editor node helper
	var parent = _get_editor_node(parent_path)
	if not parent:
		return _create_error_response("Parent node not found: %s" % parent_path)

	# Get children
	var children = []
	for child in parent.get_children():
		children.append({
			"name": child.name,
			"type": child.get_class(),
			"path": str(child.get_path()).replace(str(parent.get_path()), parent_path)
		})

	return _create_success_response({
		"parent_path": parent_path,
		"children": children
	})
