#if TOOLS
using Godot;
using System;
using ModelContextProtocol.Server;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Protocol.Transport;
using ModelContextProtocol.Protocol.Types;
using System.Text.Json;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Threading;
using System.Net;
using System.IO;
using Microsoft.AspNetCore.Builder;
using GodotDictionary=Godot.Collections.Dictionary;
using Microsoft.AspNetCore.Components.RenderTree;
using Microsoft.AspNetCore.Http;

[Tool]
public partial class GodotMCP : EditorPlugin
{
	[Signal]
	public delegate void ClientConnectedEventHandler(int id);

	[Signal]
	public delegate void ClientDisconnectedEventHandler(int id);

	[Signal]
	public delegate void CommandReceivedEventHandler(int clientId, GodotDictionary command);

	private class ClientInfo
	{
		public int ClientId { get; set; }
		public IMcpServer Server { get; set; }
		public Stream ResponseStream { get; set; }
	}

	public int GetClientCount()
	{
		return _clients.Count;
	}

	public override async void _EnterTree()
	{
		GD.Print("[MCP C# Main] Entering tree...");

		// Wait for a frame to ensure everything is properly initialized
		await ToSignal(GetTree(), "process_frame");
	}

	public GodotObject Handler { get; private set; }

	public override async void _Ready()
	{
		SetProcess(true);
		GD.Print("[MCP C# Main] Ready");

		// Create a command handler
		Handler = ClassDB.Instantiate("MCPCommandHandler").AsGodotObject();
		Handler.Call("_initialize_command_processors", this);
		
		var builder = WebApplication.CreateBuilder();

		builder.Logging.AddConsole(consoleLogOptions => consoleLogOptions.LogToStandardErrorThreshold = LogLevel.Trace);
		builder.Services
			.AddMcpServer(options =>
			{
				options.ServerInfo = new() { Name = "godot_mcp", Version = "1.2.0" };
				options.Capabilities = new()
				{
					Tools = new()
					{
						ListToolsHandler = (request, ct) =>
						{
							// Create a list of tools from all the command processors
							var tools = new List<Tool>
							{
								// Project commands
								new()
								{
									Name = "get_project_info",
									Description = "Get information about the current project.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{}}"""),
								},
								new() {
									Name = "list_project_files",
									Description = "List files in the project.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to list files from (optional)"}}}"""),
								},
								new Tool
								{
									Name = "get_project_structure",
									Description = "Get the project directory structure.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{}}"""),
								},
								new Tool
								{
									Name = "get_project_settings",
									Description = "Get project settings.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{}}"""),
								},
								new Tool
								{
									Name = "list_project_resources",
									Description = "List resources in the project.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{}}"""),
								},

								// Scene commands
								new Tool
								{
									Name = "save_scene",
									Description = "Save the current scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to save the scene (optional)"}}}"""),
								},
								new Tool
								{
									Name = "open_scene",
									Description = "Open a scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the scene"}},"required":["path"]}"""),
								},
								new Tool
								{
									Name = "get_current_scene",
									Description = "Get information about the current scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{}}"""),
								},
								new Tool
								{
									Name = "get_scene_structure",
									Description = "Get the structure of the current scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{}}"""),
								},
								new Tool
								{
									Name = "create_scene",
									Description = "Create a new scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to save the new scene"},"root_type":{"type":"string","description":"Type of the root node"}},"required":["path","root_type"]}"""),
								},

								// Node commands
								new Tool
								{
									Name = "create_node",
									Description = "Create a new node in the scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"type":{"type":"string","description":"Type of node to create"},"parent_path":{"type":"string","description":"Path to the parent node"},"name":{"type":"string","description":"Name for the new node"}},"required":["type"]}"""),
								},
								new Tool
								{
									Name = "delete_node",
									Description = "Delete a node from the scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the node to delete"}},"required":["path"]}"""),
								},
								new Tool
								{
									Name = "update_node_property",
									Description = "Update a property of a node.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the node"},"property":{"type":"string","description":"Property name"},"value":{"description":"New value for the property"}},"required":["path","property","value"]}"""),
								},
								new Tool
								{
									Name = "get_node_properties",
									Description = "Get properties of a node.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the node"}},"required":["path"]}"""),
								},
								new Tool
								{
									Name = "list_nodes",
									Description = "List nodes in the scene.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the parent node (optional)"}}}"""),
								},

								// Script commands
								new Tool
								{
									Name = "create_script",
									Description = "Create a new script.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to save the script"},"class_name":{"type":"string","description":"Class name for the script (optional)"},"extends_type":{"type":"string","description":"Base class to extend (default: Node)"}},"required":["path"]}"""),
								},
								new Tool
								{
									Name = "edit_script",
									Description = "Edit an existing script.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the script"},"content":{"type":"string","description":"New content for the script"}},"required":["path","content"]}"""),
								},
								new Tool
								{
									Name = "get_script",
									Description = "Get the content of a script.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the script"}},"required":["path"]}"""),
								},

								// Editor commands
								new Tool
								{
									Name = "get_editor_state",
									Description = "Get the current state of the editor.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{}}"""),
								},

								// File commands
								new Tool
								{
									Name = "read_file",
									Description = "Read the contents of a file.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the file"}},"required":["path"]}"""),
								},
								new Tool
								{
									Name = "write_file",
									Description = "Write content to a file.",
									InputSchema = JsonSerializer.Deserialize<JsonElement>("""{"type":"object","properties":{"path":{"type":"string","description":"Path to the file"},"content":{"type":"string","description":"Content to write"}},"required":["path","content"]}"""),
								},
							};

							return Task.FromResult(new ListToolsResult { Tools = tools });
						},

						CallToolHandler = (request, ct) =>
						{
							var sessionId = request.Server.Services.GetRequiredService<HttpContext>().Request.Query["sessionId"].ToString();

							var command = new GodotDictionary
							{
								{ "type", request.Params.Name },
								{ "commandId", request.Params.Name },
								{ "sessionId", sessionId },
								{ "params", new GodotDictionary() }
							};

							// Add the arguments to the params dictionary
							if (request.Params.Arguments != null)
							{
								var paramsDict = (GodotDictionary)command["params"];
								foreach (var kvp in request.Params.Arguments)
								{
									var value = kvp.Value;
									paramsDict[kvp.Key] = value.ValueKind switch
									{
										JsonValueKind.String => value.GetString(),
										JsonValueKind.Number when value.TryGetInt32(out int intValue) => intValue,
										JsonValueKind.Number => value.GetDouble(),
										JsonValueKind.True => true,
										JsonValueKind.False => false,
										JsonValueKind.Null => "",
										_ => value.ToString()
									};
								}
							}

							// Call the command handler
							Handler.Call("_handle_command", sessionId, command);

							// For now, just return a simple response
							return Task.FromResult(new CallToolResponse
							{
								Content = [new Content { Text = $"Command {request.Params.Name} executed successfully", Type = "text" }]
							});
						},
					}
				};
			});


		var app = builder.Build();
		app.MapMcp();

		await app.StartAsync();
	}

	public override void _Process(double delta)
	{
	}

	public override void _ExitTree()
	{
		GD.Print("[MCP C# Main] Exiting tree...");
	}
}
#endif
