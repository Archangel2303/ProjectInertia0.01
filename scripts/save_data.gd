extends Node
class_name SaveData

const SAVE_PATH := "user://recoil_save.cfg"

static func load_config() -> ConfigFile:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		# Fresh file or unreadable; start empty.
		pass
	return cfg

static func save_config(cfg: ConfigFile) -> void:
	cfg.save(SAVE_PATH)

static func get_high_score(level_id: String) -> int:
	var cfg := load_config()
	return int(cfg.get_value("highscores", level_id, 0))

static func set_high_score(level_id: String, score: int) -> void:
	var cfg := load_config()
	cfg.set_value("highscores", level_id, int(score))
	save_config(cfg)
