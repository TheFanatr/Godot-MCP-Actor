@tool
class_name MCPEditorCommands
extends MCPBaseCommandProcessor

func process_command(command_type: String, params: Dictionary) -> Dictionary:
	match command_type:
		"get_editor_state":
			return _get_editor_state(params)
		"get_selected_node":
			return _get_selected_node(params)
		"create_resource":
			return _create_resource(params)
	# Return an empty dictionary to indicate command not handled
	return {}

func _get_editor_state(params: Dictionary) -> Dictionary:
	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()

	var state = {
		"current_scene": "",
		"current_script": "",
		"selected_nodes": [],
		"is_playing": editor_interface.is_playing_scene()
	}

	# Get current scene
	var edited_scene_root = editor_interface.get_edited_scene_root()
	if edited_scene_root:
		state["current_scene"] = edited_scene_root.scene_file_path

	# Get current script if any is being edited
	var script_editor = editor_interface.get_script_editor()
	var current_script = script_editor.get_current_script()
	if current_script:
		state["current_script"] = current_script.resource_path

	# Get selected nodes
	var selection = editor_interface.get_selection()
	var selected_nodes = selection.get_selected_nodes()

	for node in selected_nodes:
		state["selected_nodes"].append({
			"name": node.name,
			"path": str(node.get_path())
		})

	return _create_success_response(state)

func _get_selected_node(params: Dictionary) -> Dictionary:
	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()
	var selection = editor_interface.get_selection()
	var selected_nodes = selection.get_selected_nodes()

	if selected_nodes.size() == 0:
		return _create_success_response({
			"selected": false,
			"message": "No node is currently selected"
		})

	var node = selected_nodes[0]  # Get the first selected node

	# Get node info
	var node_data = {
		"selected": true,
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path())
	}

	# Get script info if available
	var script = node.get_script()
	if script:
		node_data["script_path"] = script.resource_path

	# Get important properties
	var properties = {}
	var property_list = node.get_property_list()

	for prop in property_list:
		var name = prop["name"]
		if not name.begins_with("_"):  # Skip internal properties
			# Only include some common properties to avoid overwhelming data
			if name in ["position", "rotation", "scale", "visible", "modulate", "z_index"]:
				properties[name] = node.get(name)

	node_data["properties"] = properties

	return _create_success_response(node_data)

func _create_resource(params: Dictionary) -> Dictionary:
	var resource_type = params.get("resource_type", "")
	var resource_path = params.get("resource_path", "")
	var properties = params.get("properties", {})

	# Validation
	if resource_type.is_empty():
		return _create_error_response("Resource type cannot be empty")

	if resource_path.is_empty():
		return _create_error_response("Resource path cannot be empty")

	# Make sure we have an absolute path
	if not resource_path.begins_with("res://"):
		resource_path = "res://" + resource_path

	# Get editor interface
	var plugin = Engine.get_meta("GodotMCP")

	var editor_interface = plugin.get_editor_interface()

	if not ClassDB.class_exists(resource_type):
		return _create_error_response("Invalid resource type: %s" % resource_type)
	if not ClassDB.is_parent_class(resource_type, "Resource"):
		return _create_error_response("Type is not a Resource: %s" % resource_type)
	
	# Create the resource
	var resource = ClassDB.instantiate(resource_type)
	if not resource:
		return _create_error_response("Failed to instantiate resource: %s" % resource_type)

	# Set properties
	for key in properties:
		resource.set(key, properties[key])

	# Create directory if needed
	var dir = resource_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err = DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return _create_error_response("Failed to create directory: %s (Error code: %d)" % [dir, err])

	# Save the resource
	var result = ResourceSaver.save(resource, resource_path)
	if result != OK:
		return _create_error_response("Failed to save resource: %d" % result)

	# Refresh the filesystem
	editor_interface.get_resource_filesystem().scan()

	return _create_success_response({
		"resource_path": resource_path,
		"resource_type": resource_type
	})
