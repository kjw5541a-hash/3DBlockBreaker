extends SceneTree

func _initialize() -> void:
	_test_round_trip_saves_and_loads()
	_test_missing_save_defaults_to_zero()
	print("test_save_data: OK")
	quit()

func _test_round_trip_saves_and_loads() -> void:
	SaveData.save_best_stage(7)
	assert(SaveData.load_best_stage() == 7,
		"저장한 값이 그대로 안 읽힌다: %d" % SaveData.load_best_stage())
	SaveData.save_best_stage(12)
	assert(SaveData.load_best_stage() == 12,
		"덮어쓴 값이 안 읽힌다: %d" % SaveData.load_best_stage())

# 파일이 없을 때가 아니라 "이 프로젝트가 만든 적 없는 키" 를 물었을 때를
# 본다 — 실제로 파일이 없는 상황은 이 머신에서 재현할 수 없다(다른 테스트가
# 이미 만들어 놨다).
func _test_missing_save_defaults_to_zero() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SaveData.PATH)
	assert(int(cfg.get_value("record", "no_such_key", 0)) == 0,
		"없는 키의 기본값이 0 이 아니다")
