#!/usr/bin/env python3
"""Exercise the configured main scene after clean import and a class-cache upgrade.

The observer is a temporary autoload: it never replaces run/main_scene, loads a
scene, modifies saves, or drives a custom SceneTree. No cache in the real project
is changed. The upgrade case retains imported assets and all existing classes,
but removes the two classes introduced in the 3/4/8 update, as an older editor's
class index would. This catches startup compile errors even if Godot exits zero.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NEW_CLASSES = ("DelayedPressurePlate", "ReversibleRoute")
OBSERVER = r'''extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_observe.call_deferred()

func _observe() -> void:
	for frame in 12:
		await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://scenes/main_menu.tscn":
		_fail("configured main scene did not load")
		return
	var background := scene.get_node_or_null("Background") as Control
	var title := scene.get_node_or_null("Margin/VBox/Title") as Label
	var list := scene.get_node_or_null("Margin/VBox/LevelScroll/LevelList")
	if background == null or not background.is_visible_in_tree() or background.size.x < 1000:
		_fail("menu background missing or unlaid out")
		return
	if title == null or not title.is_visible_in_tree() or title.text.is_empty():
		_fail("menu title missing")
		return
	if list == null or list.get_child_count() != 10:
		_fail("expected ten menu buttons")
		return
	var first := list.get_child(0) as Button
	if first == null or first.disabled or not first.is_visible_in_tree() or first.size.y < 60:
		_fail("first menu button is not ready")
		return
	if get_tree().paused:
		_fail("menu unexpectedly paused")
		return
	print("NORMAL_MENU_OK: main_menu, background, title, 10 buttons, unpaused")
	# Use the menu's real button handler rather than loading a test scene.
	first.pressed.emit()
	for frame in 12:
		await get_tree().process_frame
	scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://scenes/level.tscn":
		_fail("menu button did not enter the first level")
		return
	var players := scene.get_node_or_null("Players")
	if players == null or players.get_child_count() != 2 or not scene.has_node("Terrain/Solid") or not scene.has_node("HUD"):
		_fail("first level did not build players, terrain and HUD")
		return
	print("NORMAL_STARTUP_OK: normal menu and first-level world/HUD ready")
	get_tree().quit(0)

func _fail(reason: String) -> void:
	push_error("NORMAL_STARTUP_FAILED: " + reason)
	get_tree().quit(1)
'''


def run(command, env, timeout=90):
    result = subprocess.run(command, env=env, cwd=ROOT, capture_output=True,
                            text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return result.returncode, result.stdout + result.stderr


def require_ok(label, code, output, marker=None):
    print(f"=== {label} ===\n{output}", flush=True)
    if code or any(line.startswith(("SCRIPT ERROR:", "ERROR:")) for line in output.splitlines()):
        raise RuntimeError(f"{label} failed (exit {code})")
    if marker and marker not in output:
        raise RuntimeError(f"{label} did not finish its assertions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    binary = shutil.which(args.godot)
    if not binary:
        parser.error("Godot not found")
    with tempfile.TemporaryDirectory(prefix="fireboy-startup-") as temporary:
        base = Path(temporary)
        project = base / "project"
        shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns(".godot", ".git", "__pycache__"))
        env = os.environ.copy()
        for key in ("HOME", "APPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            location = base / key.lower()
            location.mkdir()
            env[key] = str(location)
        observer = project / "tools" / "_normal_startup_observer.gd"
        observer.write_text(OBSERVER, encoding="utf-8")
        config = project / "project.godot"
        content = config.read_text(encoding="utf-8")
        assert 'run/main_scene="res://scenes/main_menu.tscn"' in content
        content = content.replace("[autoload]\n", '[autoload]\n\nStartupObserver="*res://tools/_normal_startup_observer.gd"\n', 1)
        config.write_text(content, encoding="utf-8")
        command = [binary, "--headless", "--path", str(project)]
        import_command = command + ["--editor", "--import", "--quit"]
        code, output = run(import_command, env)
        # Godot initializes the configured project font before its first import.
        # The existing aggregate runner has the same verified second-import step.
        if "ERROR: Error loading custom project font" in output:
            print("First import before custom-font data existed (rechecking):", flush=True)
            print("\n".join("  " + line for line in output.splitlines()), flush=True)
            code, output = run(import_command, env)
        require_ok("Clean import", code, output)
        code, output = run(command, env)
        require_ok("Normal main scene after clean import", code, output, "NORMAL_STARTUP_OK")
        cache = project / ".godot" / "global_script_class_cache.cfg"
        entries = cache.read_text(encoding="utf-8")
        for name in NEW_CLASSES:
            pattern = r'\{[^{}]*"class": &"' + name + r'"[^{}]*\},?\s*'
            entries, count = re.subn(pattern, "", entries)
            if count != 1:
                raise RuntimeError(f"Expected one cache entry for {name}, found {count}")
        cache.write_text(entries, encoding="utf-8")
        # Deliberately do NOT run the editor/importer between the cache mutation
        # and this normal game launch: that would conceal the upgrade regression.
        code, output = run(command, env)
        require_ok("Normal main scene with pre-upgrade class cache", code, output, "NORMAL_STARTUP_OK")
    print("Normal startup regression passed; project and saves were isolated.")


if __name__ == "__main__":
    main()
