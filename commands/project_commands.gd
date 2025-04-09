@tool
class_name MCPProjectCommands
extends MCPBaseCommandProcessor

func process_command(command_type: String, params: Dictionary) -> Dictionary:
	match command_type:
		"get_project_info":
			return _get_project_info(params)
		"list_project_files":
			return _list_project_files(params)
		"get_project_structure":
			return _get_project_structure(params)
		"get_project_settings":
			return _get_project_settings(params)
		"list_project_resources":
			return _list_project_resources(params)
	# Return an empty dictionary to indicate command not handled
	return {}

func _get_project_info(params: Dictionary) -> Dictionary:
	var project_name = ProjectSettings.get_setting("application/config/name", "Untitled Project")
	var project_version = ProjectSettings.get_setting("application/config/version", "1.0.0")
	var project_path = ProjectSettings.globalize_path("res://")

	# Get Godot version info and structure it as expected by the server
	var version_info = Engine.get_version_info()
	print("Raw Godot version info: ", version_info)

	# Create structured version object with the expected properties
	var structured_version = {
		"major": version_info.get("major", 0),
		"minor": version_info.get("minor", 0),
		"patch": version_info.get("patch", 0)
	}

	var result = {
		"project_name": project_name,
		"project_version": project_version,
		"project_path": project_path,
		"godot_version": structured_version,
		"current_scene": get_tree().edited_scene_root.scene_file_path if get_tree().edited_scene_root else ""
	}

	return _create_success_response(result)

func _list_project_files(params: Dictionary) -> Dictionary:
	var extensions = params.get("extensions", [])
	var files = []

	# Get all files with the specified extensions
	var dir = DirAccess.open("res://")
	if dir:
		_scan_directory(dir, "", extensions, files)
		var result = {
			"files": files
		}
		return _create_success_response(result)
	else:
		return _create_error_response("Failed to open res:// directory")

func _scan_directory(dir: DirAccess, path: String, extensions: Array, files: Array) -> void:
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			var subdir = DirAccess.open("res://" + path + file_name)
			if subdir:
				_scan_directory(subdir, path + file_name + "/", extensions, files)
		else:
			var file_path = path + file_name
			var has_valid_extension = extensions.is_empty()

			for ext in extensions:
				if file_name.ends_with(ext):
					has_valid_extension = true
					break

			if has_valid_extension:
				files.append("res://" + file_path)

		file_name = dir.get_next()

	dir.list_dir_end()

func _get_project_structure(params: Dictionary) -> Dictionary:
	var structure = {
		"directories": [],
		"file_counts": {},
		"total_files": 0
	}

	var dir = DirAccess.open("res://")
	if dir:
		_analyze_project_structure(dir, "", structure)
		return _create_success_response(structure)
	else:
		return _create_error_response("Failed to open res:// directory")

func _analyze_project_structure(dir: DirAccess, path: String, structure: Dictionary) -> void:
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			var dir_path = path + file_name + "/"
			structure["directories"].append("res://" + dir_path)

			var subdir = DirAccess.open("res://" + dir_path)
			if subdir:
				_analyze_project_structure(subdir, dir_path, structure)
		else:
			structure["total_files"] += 1

			var extension = file_name.get_extension()
			if extension in structure["file_counts"]:
				structure["file_counts"][extension] += 1
			else:
				structure["file_counts"][extension] = 1

		file_name = dir.get_next()

	dir.list_dir_end()

func _get_project_settings(params: Dictionary) -> Dictionary:
	# Get relevant project settings
	var settings = {
		"project_name": ProjectSettings.get_setting("application/config/name", "Untitled Project"),
		"project_version": ProjectSettings.get_setting("application/config/version", "1.0.0"),
		"display": {
			"width": ProjectSettings.get_setting("display/window/size/viewport_width", 1024),
			"height": ProjectSettings.get_setting("display/window/size/viewport_height", 600),
			"mode": ProjectSettings.get_setting("display/window/size/mode", 0),
			"resizable": ProjectSettings.get_setting("display/window/size/resizable", true)
		},
		"physics": {
			"2d": {
				"default_gravity": ProjectSettings.get_setting("physics/2d/default_gravity", 980)
			},
			"3d": {
				"default_gravity": ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
			}
		},
		"rendering": {
			"quality": {
				"msaa": ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d", 0)
			}
		},
		"input_map": {}
	}

	# Get input mappings
	var input_map = ProjectSettings.get_setting("input")
	if input_map:
		settings["input_map"] = input_map

	return _create_success_response(settings)

func _list_project_resources(params: Dictionary) -> Dictionary:
	var resources = {
		"scenes": [],
		"scripts": [],
		"textures": [],
		"audio": [],
		"models": [],
		"resources": []
	}

	var dir = DirAccess.open("res://")
	if dir:
		_scan_resources(dir, "", resources)
		return _create_success_response(resources)
	else:
		return _create_error_response("Failed to open res:// directory")

func _scan_resources(dir: DirAccess, path: String, resources: Dictionary) -> void:
	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			var subdir = DirAccess.open("res://" + path + file_name)
			if subdir:
				_scan_resources(subdir, path + file_name + "/", resources)
		else:
			var file_path = "res://" + path + file_name

			# Categorize by extension
			if file_name.ends_with(".tscn") or file_name.ends_with(".scn"):
				resources["scenes"].append(file_path)
			elif file_name.ends_with(".gd") or file_name.ends_with(".cs"):
				resources["scripts"].append(file_path)
			elif file_name.ends_with(".png") or file_name.ends_with(".jpg") or file_name.ends_with(".jpeg"):
				resources["textures"].append(file_path)
			elif file_name.ends_with(".wav") or file_name.ends_with(".ogg") or file_name.ends_with(".mp3"):
				resources["audio"].append(file_path)
			elif file_name.ends_with(".obj") or file_name.ends_with(".glb") or file_name.ends_with(".gltf"):
				resources["models"].append(file_path)
			elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
				resources["resources"].append(file_path)

		file_name = dir.get_next()

	dir.list_dir_end()
