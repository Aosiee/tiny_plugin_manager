# Tiny Plugin Manager

A lightweight, automatic **plugin dependency manager** and **autoload reordering tool** for Godot Engine projects. Designed to make plugin organization, dependency handling, and autoload ordering simple and predictable.

![Static Badge](https://img.shields.io/badge/Godot-4.4-blue?style=flat)
----------

## Overview

-   Automatically **sorts plugin load order** based on declared dependencies
	
-   Automatically **reorders autoloads** to match plugin dependency order
	
-   Provides **delegate methods** for plugins and autoloads to react when ready
	
-   **Tracks missing dependencies** and warns cleanly
	
-   **Manual reload button** in toolbar
	
-   **Configurable verbosity** in Project Settings
	
-   **Minimal setup, no third-party dependencies**


## Installation

1.  Copy the **Tiny Plugin Manager** into your project's `addons/` folder:

```text
addons/tiny_plugin_manager/
```

2.  Enable the plugin in **Project > Project Settings > Plugins**.
	
3.  It will automatically register itself and add a `PluginManager` autoload singleton.
	
4.  After enabling, configure verbosity level if desired:
	

Go to:  
**Project > Project Settings > tiny_plugins > plugin_manager > verbosity_level**

## How to Use

Each of your plugins should define a **plugin.cfg** with declared dependencies.

Example:

```ini
[plugin]
name="Tiny Console"
description="In-game console for logging and executing commands."
author="You"
version="1.0"
script="res://addons/tiny_console/plugin.gd"
dependencies=["Required Example"] # Example required dependency
optional_dependencies=["Optional Example"] # Example optional dependency

```

 **Dependencies**: Names of other plugins that must load first.  
 **Optional Dependencies**: Names of plugins that are used if present.

----------

## How Autoloads Are Handled

If your plugin has **autoloads** under its own folder (`addons/<plugin_name>/`),  
Tiny Plugin Manager will:

-   **Associate** those autoloads with the plugin
	
-   **Reorder** autoloads according to plugin dependency rules
	
-   **Call delegate methods** once dependencies are ready
	

**No manual configuration needed** beyond placing them in the correct folder.

----------

## Delegate Methods (Callbacks)

You can add these methods inside your **plugin.gd** or **autoloads** to know when dependencies are ready.

Method

Where to implement

Called when

`_on_dependencies_ready(dependencies: Array)`

In plugin.gd

After required dependencies are ready

`_on_optional_dependencies_ready(optional_dependencies: Array)`

In plugin.gd

After optional dependencies are ready

`_on_plugin_dependencies_ready(dependencies: Array)`

In autoloads

After required dependencies are ready

`_on_plugin_optional_dependencies_ready(optional_dependencies: Array)`

In autoloads

After optional dependencies are ready

### Example: In Plugin's `plugin.gd`

```gdscript
@tool
extends EditorPlugin

func _on_dependencies_ready():
	print("Tiny Console: Required dependencies are ready!")

func _on_optional_dependencies_ready():
	print("Tiny Console: Optional dependencies are ready!")
```

### Example: In Autoload `console_autoload.gd`

```gdscript
extends Node

func _on_plugin_dependencies_ready():
	print("Console Autoload: Dependencies ready!")

func _on_plugin_optional_dependencies_ready():
	print("Console Autoload: Optional dependencies ready!")
```

## Manual Reload

You can manually trigger a full plugin reload anytime by clicking the ** Reload Plugins** button in the Godot Editor toolbar.

-   If anything changed (plugins reordered, autoloads reordered), you will see a detailed summary popup.
	
-   If no changes happened, and it was a manual reload, you still get a success popup.

## Advanced Notes

-   **Missing dependencies** are reported in a separate popup.
	
-   **Cyclic dependencies** are detected automatically and warned.
	
-   **Optional dependencies** are handled gracefully: if missing, no errors.
	
-   **Verbose mode** (`Debug`) shows plugin folder scanning, autoload matching, and dependency resolution logs.
	
-   Settings persist using **Project Settings**, not hardcoded into scripts.

## Future Roadmap Ideas
	
-   Dependency versioning
	
-   Better cyclic dependency recovery
