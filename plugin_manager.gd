@tool
extends Node

var _plugin_info: Dictionary = {}
var _sorted_plugins: Array = []
var _already_notified: bool = false

func _ready():
	if not Engine.is_editor_hint():
		call_deferred("_runtime_prepare_plugin_info")
	print("[PluginManager] PluginManager Autoload Initialized.")

func _runtime_prepare_plugin_info():
	if _already_notified:
		return
	_already_notified = true

	var cfg = ConfigFile.new()
	var err = cfg.load("res://addons/tiny_plugin_manager/res/plugin_data.cfg")
	if err != OK:
		push_error("[PluginManager] Failed to load cached plugin data!")
		return

	_plugin_info.clear()
	for plugin_name in cfg.get_section_keys("plugin_info"):
		_plugin_info[plugin_name] = cfg.get_value("plugin_info", plugin_name, {})

	_sorted_plugins = cfg.get_value("sorted", "plugins", [])
	_notify_plugins_and_autoloads()

func get_plugin_manager_singleton() -> Object:
	if Engine.has_singleton("TinyPluginManager"): # or whatever you registered it as
		return Engine.get_singleton("TinyPluginManager")
	return null

func _notify_plugins_and_autoloads():
	for plugin_name in _sorted_plugins:
		var plugin_data = _plugin_info.get(plugin_name, {})
		var folder = plugin_data.get("folder", "")
		if folder == "":
			continue

		for child in get_tree().root.get_children():
			if child.name.begins_with("@"):
				continue # Ignore internal nodes

			var singleton = get_node_or_null("/root/" + child.name)
			if singleton and singleton.get_script() != null:
				var script_path = singleton.get_script().resource_path
				if script_path.begins_with("res://addons/" + folder + "/"):
					_notify_singleton_of_plugin(singleton, plugin_name)

func _notify_singleton_of_plugin(singleton: Node, plugin_name: String):
	var info = _plugin_info.get(plugin_name, {})

	# Send required dependency info
	if singleton.has_method("_on_plugin_dependencies_ready"):
		singleton._on_plugin_dependencies_ready(info.get("dependencies", []))

	# Send optional dependency info
	if singleton.has_method("_on_plugin_optional_dependencies_ready"):
		singleton._on_plugin_optional_dependencies_ready(info.get("optional_dependencies", []))
