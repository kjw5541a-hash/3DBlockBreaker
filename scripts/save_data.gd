# 로컬 최고 기록 하나만 저장한다. 계정도 서버도 없으니 기기 안에 남는
# ConfigFile 하나로 충분하다.
class_name SaveData
extends RefCounted

const PATH := "user://save.cfg"

static func load_best_stage() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return 0
	return int(cfg.get_value("record", "best_stage", 0))

static func save_best_stage(stage: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("record", "best_stage", stage)
	cfg.save(PATH)
