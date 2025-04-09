@tool
class_name MCPEditorScriptCommands
extends MCPBaseCommandProcessor

func process_command(command_type: String, params: Dictionary) -> Dictionary:
	match command_type:
		"execute_editor_script":
			return await _execute_editor_script(params)
	# Return an empty dictionary to indicate command not handled
	return {}

func _execute_editor_script(params: Dictionary) -> Dictionary:
	var code = params.get("code", "")

	# Validation
	if code.is_empty():
		return _create_error_response("Code cannot be empty")

	# Create a temporary script node to execute the code
	var script_node := Node.new()
	script_node.name = "EditorScriptExecutor"
	add_child(script_node)

	# Create a temporary script
	var script = GDScript.new()

	var output = []
	var error_message = ""
	var execution_result = null

	# Replace print() calls with custom_print() in the user code
	var modified_code = _replace_print_calls(code)

	# Use consistent tab indentation in the template
	var script_content = """@tool
extends Node

signal execution_completed

# Variable to store the result
var result = null
var _output_array = []
var _error_message = ""
var _parent

# Custom print function that stores output in the array
func custom_print(values):
	# Convert array of values to a single string
	var output_str = ""
	if values is Array:
		for i in range(values.size()):
			if i > 0:
				output_str += " "
			output_str += str(values[i])
	else:
		output_str = str(values)

	_output_array.append(output_str)
	print(output_str)  # Still print to the console for debugging

func run():
	print("Executing script... ready func")
	_parent = get_parent()
	var scene = get_tree().edited_scene_root

	# Execute the provided code
	var err = _execute_code()

	# If there was an error, store it
	if err != OK:
		_error_message = "Failed to execute script with error: " + str(err)

	# Signal that execution is complete
	execution_completed.emit()

func _execute_code():
	# USER CODE START
{user_code}
	# USER CODE END
	return OK
"""

	# Process the user code to ensure consistent indentation
	# This helps prevent "mixed tabs and spaces" errors
	var processed_lines = []
	var lines = modified_code.split("\n")
	for line in lines:
		# Replace any spaces at the beginning with tabs
		var processed_line = line

		# If line starts with spaces, replace with a tab
		var space_count = 0
		for i in range(line.length()):
			if line[i] == " ":
				space_count += 1
			else:
				break

		# If we found spaces at the beginning, replace with tabs
		if space_count > 0:
			# Create tabs based on space count (e.g., 4 spaces = 1 tab)
			var tabs = ""
			for _i in range(space_count / 4): # Integer division
				tabs += "\t"
			processed_line = tabs + line.substr(space_count)

		processed_lines.append(processed_line)

	var indented_code = ""
	for line in processed_lines:
		indented_code += "\t" + line + "\n"

	script_content = script_content.replace("{user_code}", indented_code)
	script.source_code = script_content

	# Check for script errors during parsing
	var error = script.reload()
	if error != OK:
		remove_child(script_node)
		script_node.queue_free()
		return _create_error_response("Script parsing error: " + str(error))

	# Assign the script to the node
	script_node.set_script(script)

	script_node.run()
	await script_node.execution_completed

	# Collect results safely by checking if properties exist
	execution_result = script_node.get("result")
	output = script_node._output_array
	error_message = script_node._error_message

	# Clean up
	remove_child(script_node)
	script_node.queue_free()

	# Build the response
	var result_data = {
		"success": error_message.is_empty(),
		"output": output
	}

	if not error_message.is_empty():
		result_data["error"] = error_message
	elif execution_result != null:
		result_data["result"] = execution_result

	# Return a temporary success response
	return _create_success_response({
		"type": "script_execution_result",
		"data": result_data
	})

# Replace print() calls with custom_print() in the user code
func _replace_print_calls(code: String) -> String:
	var regex = RegEx.new()
	# Match print statements with any content inside the parentheses
	regex.compile("print\\s*\\(([^\\)]+)\\)")

	var result = regex.search_all(code)
	var modified_code = code

	# Process matches in reverse order to avoid issues with changing string length
	for i in range(result.size() - 1, -1, -1):
		var match_obj = result[i]
		var full_match = match_obj.get_string()
		var arg_content = match_obj.get_string(1)

		# Create an array with all arguments
		var replacement = "custom_print([" + arg_content + "])"

		var start = match_obj.get_start()
		var end = match_obj.get_end()

		modified_code = modified_code.substr(0, start) + replacement + modified_code.substr(end)

	return modified_code
