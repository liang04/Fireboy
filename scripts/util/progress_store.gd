extends RefCounted
## Progress-only persistence. Never truncate the live save before a replacement is verified.
## The backup contains the previous readable generation, not the damaged primary.

static func metadata_status(cfg: ConfigFile, rating_version: int, layout_version: int) -> String:
	if not cfg.has_section("progress"):
		return "invalid"
	var rating: Variant = cfg.get_value("progress", "rating_version", 0)
	var layout: Variant = cfg.get_value("progress", "layout_version", 1)
	# A recognizable future version always wins, even if another field is damaged.
	if (rating is int and rating > rating_version) or (layout is int and layout > layout_version):
		return "future"
	if not rating is int or not layout is int or rating < 0 or layout < 1:
		return "invalid"
	var unlocked: Variant = cfg.get_value("progress", "unlocked_levels", 1)
	if not unlocked is int or unlocked < 1:
		return "invalid"
	return "valid"


static func load_progress(path: String, rating_version: int, layout_version: int) -> Dictionary:
	var primary_exists := FileAccess.file_exists(path)
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		var status := metadata_status(cfg, rating_version, layout_version)
		if status == "valid":
			return {"config": cfg, "blocked": false, "recovered": false}
		if status == "future":
			# An older game must not replace a newer game's progress with its backup.
			return {"config": null, "blocked": true, "recovered": false, "reason": "future"}
	var backup := ConfigFile.new()
	if backup.load(path + ".bak") == OK \
			and metadata_status(backup, rating_version, layout_version) == "valid":
		return {"config": backup, "blocked": false, "recovered": true}
	return {"config": null, "blocked": primary_exists or FileAccess.file_exists(path + ".bak"),
		"recovered": false, "reason": "damaged"}


static func save_progress(cfg: ConfigFile, path: String, rating_version: int, layout_version: int) -> Error:
	if metadata_status(cfg, rating_version, layout_version) != "valid":
		return ERR_INVALID_DATA
	var temporary := path + ".tmp"
	var error := cfg.save(temporary)
	if error != OK:
		return error
	var verified := ConfigFile.new()
	if verified.load(temporary) != OK \
			or metadata_status(verified, rating_version, layout_version) != "valid" \
			or verified.encode_to_text() != cfg.encode_to_text():
		return ERR_INVALID_DATA
	var current := ConfigFile.new()
	if current.load(path) == OK:
		var status := metadata_status(current, rating_version, layout_version)
		if status == "future":
			return ERR_UNAVAILABLE
		if status == "valid":
			var backup_temp := path + ".bak.tmp"
			error = DirAccess.copy_absolute(path, backup_temp)
			if error != OK:
				return error
			error = DirAccess.rename_absolute(backup_temp, path + ".bak")
			if error != OK:
				return error
	# Same-directory rename replaces the old file only after the new one is complete.
	return DirAccess.rename_absolute(temporary, path)
