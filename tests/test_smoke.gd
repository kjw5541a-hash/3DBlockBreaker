extends SceneTree

func _initialize() -> void:
	_test_runner_catches_failure()
	print("test_smoke: OK")
	quit()

func _test_runner_catches_failure() -> void:
	# 러너가 살아 있는지만 본다. Task 2 부터 진짜 검사가 들어온다.
	assert(1 + 1 == 2, "산수")
