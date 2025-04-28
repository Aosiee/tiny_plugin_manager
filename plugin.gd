@tool
extends EditorPlugin

var _plugin_info : Dictionary = {}
var _sorted_plugins : Array = []
var _missing_dependencies : Array = []
var _reload_button : Button = null
var _current_dialog : AcceptDialog = null

var _manual_reload : bool = false
var _changes_made : bool = false

enum VerbosityLevel { NONE = 0, INFO = 1, DEBUG = 2 }

func _get_verbosity() -> int:
	if not ProjectSettings.has_setting("tiny_plugins/plugin_manager/verbosity_level"):
		return VerbosityLevel.INFO
	return ProjectSettings.get_setting("tiny_plugins/plugin_manager/verbosity_level", VerbosityLevel.INFO)

func _log_info(msg: String) -> void:
	if _get_verbosity() >= VerbosityLevel.INFO:
		print("[PluginManager - INFO] " + msg)

func _log_debug(msg: String) -> void:
	if _get_verbosity() >= VerbosityLevel.DEBUG:
		print("[PluginManager - DEBUG] " + msg)

func _enter_tree() -> void:
	_register_project_settings()

	_ensure_plugin_manager_autoload()
	if not is_instance_valid(_reload_button):
		_reload_button = _create_reload_button()
		add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _reload_button)
	_reload_plugins()

func _register_project_settings():
	# Create a clean category "tiny_plugins/plugin_manager" so it appears like a folder
	ProjectSettings.add_property_info({
		"name": "tiny_plugins/plugin_manager/",
		"type": TYPE_NIL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"usage": PROPERTY_USAGE_CATEGORY
	})

	var setting_path := "tiny_plugins/plugin_manager/verbosity_level"

	if not ProjectSettings.has_setting(setting_path):
		ProjectSettings.set_setting(setting_path, VerbosityLevel.INFO)
		ProjectSettings.set_initial_value(setting_path, VerbosityLevel.INFO)

	ProjectSettings.add_property_info({
		"name": setting_path,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "None, Info, Debug",
		"usage": PROPERTY_USAGE_DEFAULT
	})

func _exit_tree() -> void:
	if _reload_button:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _reload_button)
		_reload_button.queue_free()
		_reload_button = null
	
	if _current_dialog:
		_current_dialog.queue_free()
		_current_dialog = null
	
	_remove_plugin_manager_autoload()

func _ensure_plugin_manager_autoload():
	if get_tree().root.has_node("PluginManager"):
		return
	
	add_autoload_singleton("PluginManager", "res://addons/tiny_plugin_manager/plugin_manager.gd")
	_log_info("Registered PluginManager Singleton.")
	ProjectSettings.save()

func _remove_plugin_manager_autoload():
	var autoloads = ProjectSettings.get_setting("autoload")
	if autoloads != null and autoloads.has("PluginManager"):
		remove_autoload_singleton("PluginManager")
		_log_info("Unregistered PluginManager from autoload.")
		ProjectSettings.save()

func _create_reload_button() -> Button:
	var button = Button.new()
	button.text = "\u21bb Reload Plugins"
	button.tooltip_text = "Reload plugins and check dependencies."
	button.pressed.connect(Callable(self, "_on_reload_plugins_pressed"))
	return button

func _on_reload_plugins_pressed():
	_reload_plugins(true)

func _reload_plugins(manual: bool = false):
	_manual_reload = manual
	_changes_made = false

	_missing_dependencies.clear()
	await get_tree().process_frame
	var autoload_settings = _get_all_autoloads()

	_process_plugins()
	_ensure_plugin_manager_last()
	_ensure_autoload_order()
	_notify_plugins()

	if _missing_dependencies.is_empty():
		if _manual_reload or _changes_made:
			_show_success_popup()
		else:
			_log_info("No changes detected, skipping popup.")
	else:
		_show_missing_dependencies_popup()
	
	_save_plugin_info_cache()

func _process_plugins():
	_plugin_info = _scan_plugins()
	_sorted_plugins = _sort_plugins(_plugin_info)
	
	for plugin_name in _plugin_info.keys():
		_log_debug("Plugin: %s Autoloads: %s" % [plugin_name, _plugin_info[plugin_name].get("autoloads", [])])
	
	_fix_load_order()

func _scan_plugins() -> Dictionary:
	var plugins: Dictionary = {}
	var autoload_settings: Dictionary = _get_all_autoloads()

	var dir = DirAccess.open("res://addons")
	if dir:
		dir.list_dir_begin()
		var folder_name = dir.get_next()
		while folder_name != "":
			if dir.current_is_dir() and not folder_name.begins_with("."):
				_log_debug("Checking folder: %s" % folder_name)

				var plugin_cfg_path = "res://addons/%s/plugin.cfg" % folder_name
				if FileAccess.file_exists(plugin_cfg_path):
					var cfg = ConfigFile.new()
					if cfg.load(plugin_cfg_path) == OK:
						var name: String = cfg.get_value("plugin", "name", folder_name)
						var dependencies = cfg.get_value("plugin", "dependencies", [])
						var optional_dependencies = cfg.get_value("plugin", "optional_dependencies", [])
						if typeof(dependencies) == TYPE_STRING:
							dependencies = [dependencies]
						if typeof(optional_dependencies) == TYPE_STRING:
							optional_dependencies = [optional_dependencies]

						var autoloads: Array[String] = []
						for autoload_name in autoload_settings.keys():
							var autoload_info = autoload_settings[autoload_name]
							var autoload_path: String = autoload_info.get("path", "")

							if autoload_path.begins_with("res://addons/" + folder_name):
								_log_debug("    Matched autoload '%s' to plugin %s" % [autoload_name, name])
								autoloads.append(autoload_name)

						plugins[name] = {
							"folder": folder_name,
							"dependencies": dependencies,
							"optional_dependencies": optional_dependencies,
							"autoloads": autoloads,
						}
			folder_name = dir.get_next()
		dir.list_dir_end()

	return plugins

func _sort_plugins(plugins: Dictionary) -> Array:
	var sorted = []
	var visited = {}
	for name in plugins.keys():
		_visit_plugin(name, plugins, visited, sorted, [])
	return sorted

func _visit_plugin(name: String, plugins: Dictionary, visited: Dictionary, sorted: Array, stack: Array):
	if name in stack:
		push_error("[PluginManager - ERROR] Cyclic dependency detected: %s" % ", ".join(stack + [name]))
		return
	if name in visited:
		return
	visited[name] = true

	for dep in plugins.get(name, {}).get("dependencies", []):
		if dep in plugins:
			_visit_plugin(dep, plugins, visited, sorted, stack + [name])
		else:
			push_warning("[PluginManager - WARNING] Missing dependency: %s required by %s" % [dep, name])
			_missing_dependencies.append("Missing dependency: %s required by %s" % [dep, name])

	for dep in plugins.get(name, {}).get("optional_dependencies", []):
		if dep in plugins:
			_visit_plugin(dep, plugins, visited, sorted, stack + [name])

	sorted.append(name)

func _ensure_plugin_manager_last():
	var autoloads = ProjectSettings.get_setting("autoload")
	if autoloads == null or not autoloads.has("PluginManager"):
		return

	var order = ProjectSettings.get_order("autoload")
	order.erase("PluginManager")
	order.append("PluginManager")
	ProjectSettings.set_order("autoload", order)
	ProjectSettings.save()

	_log_info("PluginManager autoload moved to last.")

func _ensure_autoload_order() -> void:
	var expected_autoloads = _get_expected_autoload_order()
	var saved_autoloads = _get_all_autoloads()

	if expected_autoloads.is_empty() or saved_autoloads.is_empty():
		_log_info("No autoloads to reorder.")
		return

	var existing_autoloads: Array = []

	for property in ProjectSettings.get_property_list():
		var prop_name: String = property.name
		if prop_name.begins_with("autoload/"):
			var autoload_name: String = prop_name.trim_prefix("autoload/")
			existing_autoloads.append(autoload_name)

	var final_order: Array = []

	for expected in expected_autoloads:
		if existing_autoloads.has(expected):
			final_order.append(expected)

	for autoload_name in existing_autoloads:
		if not final_order.has(autoload_name):
			final_order.append(autoload_name)

	for i in range(final_order.size()):
		var autoload_name = final_order[i]
		ProjectSettings.set_order("autoload/" + autoload_name, i)

	ProjectSettings.save()
	_changes_made = true
	_log_info("Autoloads reordered to match dependency order.")

func _notify_plugins():
	for plugin_name in _sorted_plugins:
		var plugin_data = _plugin_info.get(plugin_name, {})
		var folder = plugin_data.get("folder", "")
		if folder == "":
			continue

		var plugin_script_path = "res://addons/%s/plugin.gd" % folder
		if not FileAccess.file_exists(plugin_script_path):
			continue

		var plugin_script = load(plugin_script_path)
		if plugin_script == null:
			continue

		var dependencies = plugin_data.get("dependencies", [])
		var optional_dependencies = plugin_data.get("optional_dependencies", [])

		if plugin_script.has_method("_on_dependencies_ready"):
			plugin_script._on_dependencies_ready(dependencies)

		if plugin_script.has_method("_on_optional_dependencies_ready"):
			plugin_script._on_optional_dependencies_ready(optional_dependencies)

		var singleton = get_node_or_null("/root/PluginManager")
		if singleton:
			if singleton.has_method("notify_plugin_dependencies_ready"):
				singleton.notify_plugin_dependencies_ready(plugin_name)

	var singleton = get_node_or_null("/root/PluginManager")
	if singleton and singleton.has_method("notify_autoloads_ready"):
		singleton.notify_autoloads_ready(_sorted_plugins, _plugin_info)

func _notify_autoloads_only():
	var autoloads = ProjectSettings.get_setting("autoload")
	for autoload_name in autoloads.keys():
		var autoload_info = autoloads[autoload_name]
		var autoload_path = autoload_info["path"]
		for plugin_name in _sorted_plugins:
			var plugin_data = _plugin_info.get(plugin_name, {})
			var folder = plugin_data.get("folder", "")
			if folder != "" and autoload_path.begins_with("res://addons/" + folder + "/"):
				var singleton = get_node_or_null("/root/" + autoload_name)
				if singleton:
					if singleton.has_method("_on_plugin_dependencies_ready"):
						singleton._on_plugin_dependencies_ready()
					if singleton.has_method("_on_plugin_optional_dependencies_ready"):
						singleton._on_plugin_optional_dependencies_ready()

func _show_missing_dependencies_popup():
	var msg := "The following plugin dependencies are missing:\n\n"
	for dep in _missing_dependencies:
		msg += dep + "\n"

	var dialog = AcceptDialog.new()
	dialog.dialog_text = msg
	dialog.title = "Missing Plugin Dependencies"
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()

func _show_success_popup():
	if _current_dialog and _current_dialog.is_inside_tree():
		_current_dialog.queue_free()
		_current_dialog = null

	var dialog = AcceptDialog.new()
	_current_dialog = dialog
	dialog.title = "Plugin Manager - Load Order"
	dialog.min_size = Vector2(600, 400)

	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)

	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)

	# === Managed Plugins Tab ===
	var managed_tab = TextEdit.new()
	managed_tab.editable = false
	managed_tab.text = "Managed Load Order (Plugins):\n"

	for i in range(_sorted_plugins.size()):
		var plugin_name = _sorted_plugins[i]
		var plugin_data = _plugin_info.get(plugin_name, {})
		managed_tab.text += "%d. %s [Sorted]\n" % [i + 1, plugin_name]

		for dep in plugin_data.get("dependencies", []):
			managed_tab.text += "    ↳ Requires: %s (Required)\n" % dep
		for dep in plugin_data.get("optional_dependencies", []):
			managed_tab.text += "    ↳ Requires: %s (Optional)\n" % dep

	tabs.add_child(managed_tab)
	tabs.set_tab_title(0, "Managed Plugins")

	# === Total Plugins Tab ===
	var all_plugins_tab = TextEdit.new()
	all_plugins_tab.editable = false
	all_plugins_tab.text = "Total Load Order (Plugins):\n"

	var plugin_list = ProjectSettings.get_setting("editor_plugins/enabled")
	var cleaned_plugin_list = []

	if plugin_list and plugin_list.size() > 0:
		for i in range(plugin_list.size()):
			var full_path = plugin_list[i]
			var folder_name = full_path.replace("res://addons/", "").replace("/plugin.cfg", "")
			cleaned_plugin_list.append(folder_name)
			all_plugins_tab.text += "%d. %s\n" % [i + 1, folder_name]
	else:
		all_plugins_tab.text += "(No plugins enabled or setting missing)\n"

	tabs.add_child(all_plugins_tab)
	tabs.set_tab_title(1, "Total Plugins")

	# === Autoloads Tab ===
	var autoloads_tab = TextEdit.new()
	autoloads_tab.editable = false
	autoloads_tab.text = "Autoloads Load Order:\n"

	var saved_autoloads = _get_all_autoloads()
	var expected_autoloads = _get_expected_autoload_order()

	var mismatch_found := false
	var handled_autoloads: Array = []

	for i in range(_sorted_plugins.size()):
		var plugin_name = _sorted_plugins[i]
		var plugin_data = _plugin_info.get(plugin_name, {})
		var plugin_autoloads = plugin_data.get("autoloads", [])

		if plugin_autoloads.size() == 0:
			continue # No autoloads for this plugin

		# Write plugin name
		autoloads_tab.text += "%d. %s\n" % [i + 1, plugin_name]
	
		for autoload_name in plugin_autoloads:
			autoloads_tab.text += "    -> %s" % autoload_name

			if not saved_autoloads.has(autoload_name):
				mismatch_found = true
				autoloads_tab.text += " ⚠ Missing!\n"
			else:
				autoloads_tab.text += "\n"

			handled_autoloads.append(autoload_name)

	# Now list any remaining autoloads not handled (project-defined)
	var leftover_autoloads: Array = []
	
	for autoload_name in saved_autoloads.keys():
		if not handled_autoloads.has(autoload_name):
			leftover_autoloads.append(autoload_name)

	if leftover_autoloads.size() > 0:
		autoloads_tab.text += "\nProject Autoloads:\n"
		for autoload_name in leftover_autoloads:
			autoloads_tab.text += "    -> %s\n" % autoload_name

	tabs.add_child(autoloads_tab)
	tabs.set_tab_title(2, "Autoloads")

	# Final summary
	if mismatch_found:
		print("[PluginManager] Dependency issues detected in autoload load order.")
	else:
		print("[PluginManager] Autoload load order matches dependency order.")

	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered_clamped(Vector2(600, 400))

func _get_all_autoloads() -> Dictionary:
	var autoloads: Dictionary = {}

	for property in ProjectSettings.get_property_list():
		var prop_name = property.name
		if prop_name.begins_with("autoload/"):
			var autoload_name = prop_name.trim_prefix("autoload/")
			var value = ProjectSettings.get_setting(prop_name)

			var path: String = ""
			var singleton: bool = true

			if typeof(value) == TYPE_DICTIONARY:
				path = value.get("path", "")
				singleton = value.get("singleton", true)
			elif typeof(value) == TYPE_STRING: # Legacy autoload support
				path = value
				singleton = true # Assume singleton if only a path

			path = path.lstrip("*")

			autoloads[autoload_name] = {
				"path": path,
				"singleton": singleton
			}

	return autoloads

func _get_expected_autoload_order() -> Array:
	var expected_autoloads: Array = []
	for plugin_name in _sorted_plugins:
		var plugin_data = _plugin_info.get(plugin_name, {})
		for autoload_name in plugin_data.get("autoloads", []):
			expected_autoloads.append(autoload_name)
	return expected_autoloads

func _fix_load_order() -> void:
	var plugin_list : Array = ProjectSettings.get_setting("editor_plugins/enabled", [])
	if plugin_list.is_empty():
		push_warning("[PluginManager] No enabled plugins to fix.")
		return
	
	# Map from plugin NAME (from plugin.cfg) to plugin path (full path)
	var path_by_plugin_name : Dictionary = {}
	for full_path in plugin_list:
		var folder_name = full_path.replace("res://addons/", "").replace("/plugin.cfg", "")
		# Find plugin name matching folder
		for plugin_name in _plugin_info.keys():
			if _plugin_info[plugin_name].folder == folder_name:
				path_by_plugin_name[plugin_name] = full_path
				break

	var new_plugin_list : Array = []
	for plugin_name in _sorted_plugins:
		if path_by_plugin_name.has(plugin_name):
			new_plugin_list.append(path_by_plugin_name[plugin_name])

	# Append any leftover plugins that PluginManager isn't tracking
	for full_path in plugin_list:
		if not new_plugin_list.has(full_path):
			new_plugin_list.append(full_path)

	if new_plugin_list != plugin_list:
		_log_info("Re-ordering plugin load order!")
		ProjectSettings.set_setting("editor_plugins/enabled", new_plugin_list)
		ProjectSettings.save()
		_changes_made = true
	else:
		_log_info("Plugin load order already correct.")

func get_plugin_info() -> Dictionary:
	return _plugin_info

func get_sorted_plugins() -> Array:
	return _sorted_plugins

func _save_plugin_info_cache():
	_log_info("Saving Plugin Data")
	var cfg = ConfigFile.new()
	
	for plugin_name in _plugin_info.keys():
		var data = _plugin_info[plugin_name]
		cfg.set_value("plugin_info", plugin_name, data)

	cfg.set_value("sorted", "plugins", _sorted_plugins)

	cfg.save("res://addons/tiny_plugin_manager/res/plugin_data.cfg")
