@tool
class_name MCPScriptCommands
extends MCPBaseCommandProcessor

func process_command(command_type: String, params: Dictionary) -> Dictionary:
	match command_type:
		"create_script":
			# This is a special case because it's a coroutine
			return await _create_script(params)
		"edit_script":
			return _edit_script(params)
		"get_script":
			return _get_script(params)
		"get_script_metadata":
			return _get_script_metadata(params)
		"get_current_script":
			return _get_current_script(params)
		"create_script_template":
			return _create_script_template(params)
	# Return an empty dictionary to indicate command not handled
	return {}

func _create_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	var content = params.get("content", "")
	var node_path = params.get("node_path", "")

	# Validation
	if script_path.is_empty():
		return _create_error_response("Script path cannot be empty")

	# Make sure we have an absolute path
	if not script_path.begins_with("res://"):
		script_path = "res://" + script_path

	if not script_path.ends_with(".gd"):
		script_path += ".gd"

	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()
	var script_editor = editor_interface.get_script_editor()

	# Create the directory if it doesn't exist
	var dir = script_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err = DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return _create_error_response("Failed to create directory: %s (Error code: %d)" % [dir, err])

	# Create the script file
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return _create_error_response("Failed to create script file: %s" % script_path)

	file.store_string(content)
	file = null  # Close the file

	# Refresh the filesystem
	editor_interface.get_resource_filesystem().scan()

	# Attach the script to a node if specified
	if not node_path.is_empty():
		var node = _get_editor_node(node_path)
		if not node:
			return _create_error_response("Node not found: %s" % node_path)

		# Wait for script to be recognized in the filesystem
		await get_tree().create_timer(0.5).timeout

		var script = load(script_path)
		if not script:
			return _create_error_response("Failed to load script: %s" % script_path)

		# Use undo/redo for script assignment
		var undo_redo = _get_undo_redo()
		if not undo_redo:
			# Fallback method if we can't get undo/redo
			node.set_script(script)
			_mark_scene_modified()
		else:
			# Use undo/redo for proper editor integration
			undo_redo.create_action("Assign Script")
			undo_redo.add_do_method(node, "set_script", script)
			undo_redo.add_undo_method(node, "set_script", node.get_script())
			undo_redo.commit_action()

		# Mark the scene as modified
		_mark_scene_modified()

	# Open the script in the editor
	var script_resource = load(script_path)
	if script_resource:
		editor_interface.edit_script(script_resource)

	return _create_success_response({
		"script_path": script_path,
		"node_path": node_path
	})

func _edit_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	var content = params.get("content", "")

	# Validation
	if script_path.is_empty():
		return _create_error_response("Script path cannot be empty")

	if content.is_empty():
		return _create_error_response("Content cannot be empty")

	# Make sure we have an absolute path
	if not script_path.begins_with("res://"):
		script_path = "res://" + script_path

	# Check if the file exists
	if not FileAccess.file_exists(script_path):
		return _create_error_response("Script file not found: %s" % script_path)

	# Edit the script file
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return _create_error_response("Failed to open script file: %s" % script_path)

	file.store_string(content)
	file = null  # Close the file

	return _create_success_response({
		"script_path": script_path
	})

func _get_script(params: Dictionary) -> Dictionary:
	var script_path = params.get("script_path", "")
	var node_path = params.get("node_path", "")

	# Validation - either script_path or node_path must be provided
	if script_path.is_empty() and node_path.is_empty():
		return _create_error_response("Either script_path or node_path must be provided")

	# If node_path is provided, get the script from the node
	if not node_path.is_empty():
		var node = _get_editor_node(node_path)
		if not node:
			return _create_error_response("Node not found: %s" % node_path)

		var script = node.get_script()
		if not script:
			return _create_error_response("Node does not have a script: %s" % node_path)

		script_path = script.resource_path

	# Make sure we have an absolute path
	if not script_path.begins_with("res://"):
		script_path = "res://" + script_path

	# Check if the file exists
	if not FileAccess.file_exists(script_path):
		return _create_error_response("Script file not found: %s" % script_path)

	# Read the script file
	var file = FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return _create_error_response("Failed to open script file: %s" % script_path)

	var content = file.get_as_text()
	file = null  # Close the file

	return _create_success_response({
		"script_path": script_path,
		"content": content
	})

func _get_script_metadata(params: Dictionary) -> Dictionary:
	var path = params.get("path", "")

	# Validation
	if path.is_empty():
		return _create_error_response("Script path cannot be empty")

	if not path.begins_with("res://"):
		path = "res://" + path

	if not FileAccess.file_exists(path):
		return _create_error_response("Script file not found: " + path)

	# Load the script
	var script = load(path)
	if not script:
		return _create_error_response("Failed to load script: " + path)

	# Extract script metadata
	var metadata = {
		"path": path,
		"language": "gdscript" if path.ends_with(".gd") else "csharp" if path.ends_with(".cs") else "unknown"
	}

	# Attempt to get script class info
	var class_name_str = ""
	var extends_class = ""

	# Read the file to extract class_name and extends info
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var content = file.get_as_text()

		# Extract class_name
		var class_regex = RegEx.new()
		class_regex.compile("class_name\\s+([a-zA-Z_][a-zA-Z0-9_]*)")
		var result = class_regex.search(content)
		if result:
			class_name_str = result.get_string(1)

		# Extract extends
		var extends_regex = RegEx.new()
		extends_regex.compile("extends\\s+([a-zA-Z_][a-zA-Z0-9_]*)")
		result = extends_regex.search(content)
		if result:
			extends_class = result.get_string(1)

		# Add to metadata
		metadata["class_name"] = class_name_str
		metadata["extends"] = extends_class

		# Try to extract methods and signals
		var methods = []
		var signals = []

		var method_regex = RegEx.new()
		method_regex.compile("func\\s+([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(")
		var method_matches = method_regex.search_all(content)

		for match_result in method_matches:
			methods.append(match_result.get_string(1))

		var signal_regex = RegEx.new()
		signal_regex.compile("signal\\s+([a-zA-Z_][a-zA-Z0-9_]*)")
		var signal_matches = signal_regex.search_all(content)

		for match_result in signal_matches:
			signals.append(match_result.get_string(1))

		metadata["methods"] = methods
		metadata["signals"] = signals

	return _create_success_response(metadata)

func _get_current_script(params: Dictionary) -> Dictionary:
	# Get editor plugin and interfaces
	var plugin = Engine.get_meta("GodotMCP")
	if not plugin:
		return _create_error_response("GodotMCPPlugin not found in Engine metadata")

	var editor_interface = plugin.get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	var current_script = script_editor.get_current_script()

	if not current_script:
		return _create_success_response({
			"script_found": false,
			"message": "No script is currently being edited"
		})

	var script_path = current_script.resource_path

	# Read the script content
	var file = FileAccess.open(script_path, FileAccess.READ)
	if not file:
		return _create_error_response("Failed to open script file: %s" % script_path)

	var content = file.get_as_text()
	file = null  # Close the file

	return _create_success_response({
		"script_found": true,
		"script_path": script_path,
		"content": content
	})

func _create_script_template(params: Dictionary) -> Dictionary:
	var extends_type = params.get("extends_type", "Node")
	var class_name_str = params.get("class_name", "")
	var include_ready = params.get("include_ready", true)
	var include_process = params.get("include_process", false)
	var include_physics = params.get("include_physics", false)
	var include_input = params.get("include_input", false)

	# Generate script content
	var content = "extends " + extends_type + "\n\n"

	if not class_name_str.is_empty():
		content += "class_name " + class_name_str + "\n\n"

	# Add variables section placeholder
	content += "# Member variables here\n\n"

	# Add ready function
	if include_ready:
		content += "func _ready():\n\tpass\n\n"

	# Add process function
	if include_process:
		content += "func _process(delta):\n\tpass\n\n"

	# Add physics process function
	if include_physics:
		content += "func _physics_process(delta):\n\tpass\n\n"

	# Add input function
	if include_input:
		content += "func _input(event):\n\tpass\n\n"

	return _create_success_response({
		"content": content
	})
