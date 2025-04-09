@tool
class_name MCPSceneCommands
extends MCPBaseCommandProcessor

func process_command(command_type: String, params: Dictionary) -> Dictionary:
	match command_type:
		"save_scene":
			return _save_scene(params)
		"open_scene":
			return _open_scene(params)
		"get_current_scene":
			return _get_current_scene(params)
		"get_scene_structure":
			return _get_scene_structure(params)
		"create_scene":
			return _create_scene(params)
	# Return an empty dictionary to indicate command not handled
	return {}

func _save_scene(params: Dictionary) -> Dictionary:
	var path = params.get("path", "")

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	# If no path provided, use the current scene path
	if path.is_empty() and edited_scene_root:
		path = edited_scene_root.scene_file_path

	# Validation
	if path.is_empty():
		return _create_error_response("Scene path cannot be empty")

	# Make sure we have an absolute path
	if not path.begins_with("res://"):
		path = "res://" + path

	if not path.ends_with(".tscn"):
		path += ".tscn"

	# Check if we have an edited scene
	if not edited_scene_root:
		return _create_error_response("No scene is currently being edited")

	# Save the scene
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(edited_scene_root)
	if result != OK:
		return _create_error_response("Failed to pack scene: %d" % result)

	result = ResourceSaver.save(packed_scene, path)
	if result != OK:
		return _create_error_response("Failed to save scene: %d" % result)

	return _create_success_response({
		"scene_path": path
	})

func _open_scene(params: Dictionary) -> Dictionary:
	var path = params.get("path", "")

	# Validation
	if path.is_empty():
		return _create_error_response("Scene path cannot be empty")

	# Make sure we have an absolute path
	if not path.begins_with("res://"):
		path = "res://" + path

	# Check if the file exists
	if not FileAccess.file_exists(path):
		return _create_error_response("Scene file not found: %s" % path)

	# Since we can't directly open scenes in tool scripts,
	# we need to defer to the plugin which has access to EditorInterface
	var plugin = Engine.get_meta("GodotMCP") if Engine.has_meta("GodotMCP") else null

	if plugin and plugin.has_method("get_editor_interface"):
		var editor_interface = plugin.get_editor_interface()
		editor_interface.open_scene_from_path(path)
		return _create_success_response({
			"scene_path": path
		})
	else:
		return _create_error_response("Cannot access EditorInterface. Please open the scene manually: %s" % path)

func _get_current_scene(params: Dictionary) -> Dictionary:
	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()

	if not edited_scene_root:
		print("No scene is currently being edited")
		# Instead of returning an error, return a valid response with empty/default values
		return _create_success_response({
			"scene_path": "None",
			"root_node_type": "None",
			"root_node_name": "None"
		})

	var scene_path = edited_scene_root.scene_file_path
	if scene_path.is_empty():
		scene_path = "Untitled"

	print("Current scene path: ", scene_path)
	print("Root node type: ", edited_scene_root.get_class())
	print("Root node name: ", edited_scene_root.name)

	return _create_success_response({
		"scene_path": scene_path,
		"root_node_type": edited_scene_root.get_class(),
		"root_node_name": edited_scene_root.name
	})

func _get_scene_structure(params: Dictionary) -> Dictionary:
	var path = params.get("path", "")

	# Validation
	if path.is_empty():
		return _create_error_response("Scene path cannot be empty")

	if not path.begins_with("res://"):
		path = "res://" + path

	if not FileAccess.file_exists(path):
		return _create_error_response("Scene file not found: " + path)

	# Load the scene to analyze its structure
	var packed_scene = load(path)
	if not packed_scene:
		return _create_error_response("Failed to load scene: " + path)

	# Create a temporary instance to analyze
	var scene_instance = packed_scene.instantiate()
	if not scene_instance:
		return _create_error_response("Failed to instantiate scene: " + path)

	# Get the scene structure
	var structure = _get_node_structure(scene_instance)

	# Clean up the temporary instance
	scene_instance.queue_free()

	# Return the structure
	return _create_success_response({
		"path": path,
		"structure": structure
	})

func _get_node_structure(node: Node) -> Dictionary:
	var structure = {
		"name": node.name,
		"type": node.get_class(),
		"path": node.get_path()
	}

	# Get script information
	var script = node.get_script()
	if script:
		structure["script"] = script.resource_path

	# Get important properties
	var properties = {}
	var property_list = node.get_property_list()

	for prop in property_list:
		var name = prop["name"]
		# Filter to include only the most useful properties
		if not name.begins_with("_") and name not in ["script", "children", "position", "rotation", "scale"]:
			continue

		# Skip properties that are default values
		if name == "position" and node.position == Vector2():
			continue
		if name == "rotation" and node.rotation == 0:
			continue
		if name == "scale" and node.scale == Vector2(1, 1):
			continue

		properties[name] = node.get(name)

	structure["properties"] = properties

	# Get children
	var children = []
	for child in node.get_children():
		children.append(_get_node_structure(child))

	structure["children"] = children

	return structure

func _create_scene(params: Dictionary) -> Dictionary:
	var path = params.get("path", "")
	var root_node_type = params.get("root_node_type", "Node")

	# Validation
	if path.is_empty():
		return _create_error_response("Scene path cannot be empty")

	# Make sure we have an absolute path
	if not path.begins_with("res://"):
		path = "res://" + path

	# Ensure path ends with .tscn
	if not path.ends_with(".tscn"):
		path += ".tscn"

	# Create directory structure if it doesn't exist
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var dir = DirAccess.open("res://")
		if dir:
			dir.make_dir_recursive(dir_path.trim_prefix("res://"))

	# Check if file already exists
	if FileAccess.file_exists(path):
		return _create_error_response("Scene file already exists: %s" % path)

	# Create the root node of the specified type
	var root_node = null

	match root_node_type:
		"Node":
			root_node = Node.new()
		"Node2D":
			root_node = Node2D.new()
		"Node3D", "Spatial":
			root_node = Node3D.new()
		"Control":
			root_node = Control.new()
		"CanvasLayer":
			root_node = CanvasLayer.new()
		"Panel":
			root_node = Panel.new()
		_:
			# Attempt to create a custom class if built-in type not recognized
			if ClassDB.class_exists(root_node_type):
				root_node = ClassDB.instantiate(root_node_type)
			else:
				return _create_error_response("Invalid root node type: %s" % root_node_type)

	# Give the root node a name based on the file name
	var file_name = path.get_file().get_basename()
	root_node.name = file_name

	# Create a packed scene
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(root_node)
	if result != OK:
		root_node.free()
		return _create_error_response("Failed to pack scene: %d" % result)

	# Save the packed scene to disk
	result = ResourceSaver.save(packed_scene, path)
	if result != OK:
		root_node.free()
		return _create_error_response("Failed to save scene: %d" % result)

	# Clean up
	root_node.free()

	# Try to open the scene in the editor
	var plugin = Engine.get_meta("GodotMCP") if Engine.has_meta("GodotMCP") else null
	if plugin and plugin.has_method("get_editor_interface"):
		var editor_interface = plugin.get_editor_interface()
		editor_interface.open_scene_from_path(path)

	return _create_success_response({
		"scene_path": path,
		"root_node_type": root_node_type
	})
